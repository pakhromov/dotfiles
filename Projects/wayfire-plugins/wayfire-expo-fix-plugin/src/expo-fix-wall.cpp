#include "expo-fix-wall.hpp"
#include "wayfire/scene-input.hpp"
#include "wayfire/scene-operations.hpp"
#include "wayfire/workspace-stream.hpp"
#include "wayfire/scene-render.hpp"
#include "wayfire/scene.hpp"
#include "wayfire/region.hpp"
#include "wayfire/core.hpp"

#include <glm/gtc/matrix_transform.hpp>

namespace wf
{
template<class Data> using per_workspace_map_t = std::map<int, std::map<int, Data>>;

class expo_fix_wall_t::workspace_wall_node_t : public scene::node_t
{
    class wwall_render_instance_t : public scene::render_instance_t
    {
        std::shared_ptr<workspace_wall_node_t> self;
        per_workspace_map_t<std::vector<scene::render_instance_uptr>> instances;

        scene::damage_callback push_damage;
        wf::signal::connection_t<scene::node_damage_signal> on_wall_damage =
            [=] (scene::node_damage_signal *ev)
        {
            push_damage(ev->region);
        };

        wf::geometry_t get_workspace_rect(wf::point_t ws)
        {
            auto output_size = self->wall->output->get_screen_size();
            return {
                .x     = (double)(ws.x * (output_size.width + self->wall->gap_size)),
                .y     = (double)(ws.y * (output_size.height + self->wall->gap_size)),
                .width = (double)output_size.width,
                .height = (double)output_size.height,
            };
        }

      public:
        wwall_render_instance_t(workspace_wall_node_t *self,
            scene::damage_callback push_damage)
        {
            this->self = std::dynamic_pointer_cast<workspace_wall_node_t>(self->shared_from_this());
            this->push_damage = push_damage;
            self->connect(&on_wall_damage);

            for (int i = 0; i < (int)self->workspaces.size(); i++)
            {
                for (int j = 0; j < (int)self->workspaces[i].size(); j++)
                {
                    auto push_damage_child = [=] (const wf::regionf_t& damage)
                    {
                        // Store the damage because we'll have to update the buffers
                        self->aux_buffer_damage[i][j] |= damage;
                        for (auto& sc : self->aux_copies[i][j])
                        {
                            sc.dirty |= damage;
                        }

                        wf::regionf_t our_damage;
                        for (auto& rect : damage)
                        {
                            wf::geometry_t box = geometry_from_pixman_box(rect);
                            box = box + wf::origin(get_workspace_rect({i, j}));
                            auto A = self->wall->viewport;
                            auto B = self->get_bounding_box();
                            our_damage |= scale_box(A, B, box);
                        }

                        // Also damage the 'screen' after transforming damage
                        if (!our_damage.empty())
                        {
                            push_damage(our_damage);
                        }
                    };

                    self->workspaces[i][j]->gen_render_instances(instances[i][j],
                        push_damage_child, self->wall->output);
                }
            }
        }

        static double damage_sum_area(const wf::regionf_t& damage)
        {
            double sum = 0;
            for (const auto& rect : damage)
            {
                sum += (rect.y2 - rect.y1) * (rect.x2 - rect.x1);
            }

            return sum;
        }

        bool consider_rescale_workspace_buffer(int i, int j, const wf::regionf_t& visible_damage)
        {
            // In general, when rendering the auxilliary buffers for each workspace, we can render the
            // workspace thumbnails in a lower resolution, because at the end they are shown scaled.
            // This helps with performance and uses less GPU power.
            //
            // However, the situation is tricky because during the Expo animation the optimal render
            // scale constantly changes. Thus, in some cases it is actually far from optimal to rescale
            // on every frame - it is often better to just keep the buffers from the old scale.
            //
            // Nonetheless, we need to make sure to rescale when this makes sense, and to avoid visual
            // artifacts.
            //
            // The full-resolution buffer is the source of truth for the downscaled presentation
            // copies, so it is always kept at scale 1.0; scaled rendering happens by blitting from
            // it (see ensure_scaled_copy) instead of re-rendering the workspace at another scale.
            auto bbox = self->workspaces[i][j]->get_bounding_box();
            if (self->aux_buffer_current_scale[i][j] < 1.0)
            {
                self->aux_buffer_current_scale[i][j]  = 1.0;
                self->aux_buffer_current_subbox[i][j] = std::nullopt;
                self->aux_buffer_damage[i][j] |= bbox;
                return true;
            }

            return false;
        }

        static constexpr std::array<float, 1> copy_scales = {0.5f};

        // Choose the presentation copy for the given on-screen scale of a workspace:
        // the smallest copy which still has at least as much resolution as needed.
        // -1 stands for the full-resolution buffer.
        static int pick_copy_level(double quad_scale)
        {
            int level = -1;
            for (int l = 0; l < (int)copy_scales.size(); l++)
            {
                if (quad_scale <= copy_scales[l])
                {
                    level = l;
                }
            }

            return level;
        }

        // Refresh the given presentation copy so that it contains the workspace's current
        // contents. If a finer buffer (the full-resolution buffer or a larger copy) is already
        // up-to-date for the stale region, the copy is refreshed with a cheap blit from it.
        // Otherwise, the workspace is rendered directly into the copy at the copy's scale:
        // capturing content at the scale it is displayed at costs a fraction of a full-resolution
        // capture, and the full-resolution buffer can still be rendered later if it is ever
        // needed (its pending damage is tracked independently in aux_buffer_damage).
        void refresh_copy(int i, int j, int level)
        {
            auto bbox = self->workspaces[i][j]->get_bounding_box();
            auto& sc  = self->aux_copies[i][j][level];
            if (sc.buffer.allocate(wf::dimensions(bbox),
                self->wall->output->handle->scale * copy_scales[level],
                wf::buffer_allocation_hints_t{
                    .needs_alpha = false,
                    .hdr_linear  = self->wall->output && self->wall->output->is_hdr(),
                }) != buffer_reallocation_result_t::SAME)
            {
                sc.valid = false;
            }

            wf::regionf_t needed = sc.valid ? (sc.dirty & bbox) : wf::regionf_t{bbox};
            if (needed.empty())
            {
                return;
            }

            wf::auxilliary_buffer_t *source = nullptr;
            if ((level > 0) && self->aux_copies[i][j][level - 1].valid &&
                (self->aux_copies[i][j][level - 1].dirty & needed).empty())
            {
                source = &self->aux_copies[i][j][level - 1].buffer;
            } else if ((self->aux_buffer_damage[i][j] & needed).empty())
            {
                source = &self->aux_buffers[i][j];
            }

            if (source)
            {
                const auto src_size = source->get_size();
                const auto dst_size = sc.buffer.get_size();
                const auto ext = needed.get_extents();
                const double sx = src_size.width / std::max(1.0, bbox.width);
                const double sy = src_size.height / std::max(1.0, bbox.height);
                const double dx = dst_size.width / std::max(1.0, bbox.width);
                const double dy = dst_size.height / std::max(1.0, bbox.height);
                sc.buffer.get_renderbuffer().blit(*source,
                    {(ext.x1 - bbox.x) * sx, (ext.y1 - bbox.y) * sy,
                        (ext.x2 - ext.x1) * sx, (ext.y2 - ext.y1) * sy},
                    {(ext.x1 - bbox.x) * dx, (ext.y1 - bbox.y) * dy,
                        (ext.x2 - ext.x1) * dx, (ext.y2 - ext.y1) * dy});
            } else
            {
                wf::render_target_t target{sc.buffer};
                target.geometry = bbox;
                target.scale    = self->wall->output->handle->scale * copy_scales[level];

                render_pass_params_t params;
                params.instances = &instances[i][j];
                params.damage    = needed;
                params.reference_output = self->wall->output;
                params.target = target;
                params.flags  = RPASS_EMIT_SIGNALS;
                wf::render_pass_t::run(params);
            }

            sc.valid = true;
            sc.dirty.clear();
        }

        void schedule_instructions(
            std::vector<scene::render_instruction_t>& instructions,
            const wf::render_target_t& target, wf::regionf_t& damage) override
        {
            // Update workspaces in a render pass
            for (int i = 0; i < (int)self->workspaces.size(); i++)
            {
                for (int j = 0; j < (int)self->workspaces[i].size(); j++)
                {
                    const auto ws_bbox     = self->wall->get_workspace_rectangle({i, j});
                    auto visible_box       =
                        geometry_intersection(self->wall->viewport, ws_bbox) - wf::origin(ws_bbox);
                    if (self->wall->viewport_animating)
                    {
                        // While the viewport is animating, workspaces are continuously being
                        // revealed. Update the whole workspace right away, so that the content
                        // capture happens on the first animation frame, which is visually still
                        // static, instead of in the middle of the animation where a dropped
                        // frame is visible as stutter.
                        visible_box = self->workspaces[i][j]->get_bounding_box();
                    }

                    // Pick the buffer matching the current on-screen scale of the workspace.
                    // Sampling (and capturing) content at roughly the displayed size instead of
                    // minifying a full-resolution buffer keeps both the capture cost and the
                    // per-frame read traffic proportional to the output size, which matters a
                    // lot on memory-bandwidth-limited GPUs (e.g. NVIDIA at idle clocks).
                    const auto render_geometry =
                        wf::scale_box(self->wall->viewport, self->get_bounding_box(), ws_bbox);
                    const double quad_scale = render_geometry.width / std::max(1.0, ws_bbox.width);
                    int level = pick_copy_level(quad_scale);

                    if (self->wall->viewport_animating && (level < 0))
                    {
                        // While the viewport is animating, only the workspace at the center of
                        // the viewport (the one filling the screen at the start or end of the
                        // zoom) is worth a full-resolution capture. The other workspaces are
                        // only ever seen at a small scale or briefly in motion, so they are
                        // kept at the first copy level: this avoids capturing all of them at
                        // full resolution, and avoids re-blitting all copies at once when the
                        // animation crosses the copy threshold.
                        const double cx = self->wall->viewport.x + self->wall->viewport.width / 2;
                        const double cy = self->wall->viewport.y + self->wall->viewport.height / 2;
                        const auto ws_rect = self->wall->get_workspace_rectangle({i, j});
                        const bool anchor  =
                            (cx >= ws_rect.x) && (cx < ws_rect.x + ws_rect.width) &&
                            (cy >= ws_rect.y) && (cy < ws_rect.y + ws_rect.height);
                        if (!anchor)
                        {
                            level = 0;
                        }
                    }

                    if (level < 0)
                    {
                        wf::regionf_t visible_damage = self->aux_buffer_damage[i][j] & visible_box;
                        if (consider_rescale_workspace_buffer(i, j, visible_damage))
                        {
                            visible_damage |= visible_box;
                        }

                        if (!visible_damage.empty())
                        {
                            wf::render_target_t aux{self->aux_buffers[i][j]};
                            aux.subbuffer = self->aux_buffer_current_subbox[i][j];
                            aux.geometry  = self->workspaces[i][j]->get_bounding_box();
                            aux.scale     = self->wall->output->handle->scale;

                            render_pass_params_t params;
                            params.instances = &instances[i][j];
                            params.damage    = visible_damage;
                            params.reference_output = self->wall->output;
                            params.target = aux;
                            params.flags  = RPASS_EMIT_SIGNALS;
                            wf::render_pass_t::run(params);

                            self->aux_buffer_damage[i][j] ^= visible_damage;
                        }
                    } else
                    {
                        refresh_copy(i, j, level);
                    }

                    self->aux_present_level[i][j] = level;
                }
            }

            // Render the wall
            instructions.push_back(scene::render_instruction_t{
                    .instance = this,
                    .target   = target,
                    .damage   = damage & self->get_bounding_box(),
                });

            damage ^= self->get_bounding_box();
        }

        void render(const wf::scene::render_instruction_t& data) override
        {
            // The workspace buffers are opaque and are drawn without blending, so the background
            // only needs to be cleared where it will actually remain visible (the gaps between
            // workspaces). The workspace rectangles are inset by one pixel so that any subpixel
            // rounding at the quad edges is covered by the clear.
            wf::regionf_t clear_region = data.damage;
            for (int i = 0; i < (int)self->workspaces.size(); i++)
            {
                for (int j = 0; j < (int)self->workspaces[i].size(); j++)
                {
                    auto render_geometry = wf::scale_box(self->wall->viewport,
                        self->get_bounding_box(), get_workspace_rect({i, j}));
                    if ((render_geometry.width > 2) && (render_geometry.height > 2))
                    {
                        clear_region ^= wf::geometry_t{
                            render_geometry.x + 1, render_geometry.y + 1,
                            render_geometry.width - 2, render_geometry.height - 2};
                    }
                }
            }

            data.pass->clear(clear_region, self->wall->background_color);

            for (int i = 0; i < (int)self->workspaces.size(); i++)
            {
                for (int j = 0; j < (int)self->workspaces[i].size(); j++)
                {
                    auto box = get_workspace_rect({i, j});
                    auto A   = self->wall->viewport;
                    auto B   = self->get_bounding_box();
                    auto render_geometry = wf::scale_box(A, B, box);

                    int level = -1;
                    if (auto it = self->aux_present_level[i].find(j);
                        it != self->aux_present_level[i].end())
                    {
                        level = it->second;
                    }

                    const bool use_copy = (level >= 0) && self->aux_copies[i][j][level].valid;
                    auto& buffer = use_copy ?
                        self->aux_copies[i][j][level].buffer : self->aux_buffers[i][j];

                    float dim = self->wall->get_color_for_workspace({i, j});
                    const auto& subbox = self->aux_buffer_current_subbox[i][j];

                    auto tex = wf::texture_t::from_aux(buffer);
                    tex->set_filter_mode(WLR_SCALE_FILTER_BILINEAR);
                    if (!use_copy && subbox.has_value())
                    {
                        tex->set_source_box(wlr_fbox{
                                1.0 * subbox->x,
                                1.0 * subbox->y,
                                1.0 * subbox->width,
                                1.0 * subbox->height});
                    }

                    data.pass->add_texture(tex, data.target, render_geometry, data.damage);
                    if (dim < 1.0)
                    {
                        data.pass->add_rect({0, 0, 0, 1.0 - dim}, data.target,
                            render_geometry, data.damage);
                    }
                }
            }

            self->wall->render_wall(data.target, data.damage);
        }

        void compute_visibility(wf::output_t *output, wf::regionf_t& visible) override
        {
            for (int i = 0; i < (int)self->workspaces.size(); i++)
            {
                for (int j = 0; j < (int)self->workspaces[i].size(); j++)
                {
                    wf::regionf_t ws_region{self->workspaces[i][j]->get_bounding_box()};
                    for (auto& ch : this->instances[i][j])
                    {
                        ch->compute_visibility(output, ws_region);
                    }
                }
            }
        }
    };

  public:
    std::map<std::pair<int, int>, float> render_colors;

    workspace_wall_node_t(expo_fix_wall_t *wall) : node_t(false)
    {
        this->wall  = wall;
        auto [w, h] = wall->output->wset()->get_workspace_grid_size();
        workspaces.resize(w);
        for (int i = 0; i < w; i++)
        {
            for (int j = 0; j < h; j++)
            {
                auto node = std::make_shared<workspace_stream_node_t>(
                    wall->output, wf::point_t{i, j});
                workspaces[i].push_back(node);

                auto bbox = workspaces[i][j]->get_bounding_box();

                aux_buffers[i][j].allocate(wf::dimensions(bbox), wall->output->handle->scale,
                    wf::buffer_allocation_hints_t{
                        .needs_alpha = false,
                        .hdr_linear  = wall->output && wall->output->is_hdr(),
                    });
                aux_buffer_damage[i][j] |= bbox;
                aux_buffer_current_scale[i][j]  = 1.0;
                aux_buffer_current_subbox[i][j] = std::nullopt;
            }
        }
    }

    virtual void gen_render_instances(
        std::vector<scene::render_instance_uptr>& instances,
        scene::damage_callback push_damage, wf::output_t *shown_on) override
    {
        if (shown_on != this->wall->output)
        {
            return;
        }

        instances.push_back(std::make_unique<wwall_render_instance_t>(
            this, push_damage));
    }

    std::string stringify() const override
    {
        return "workspace-wall " + stringify_flags();
    }

    wf::geometry_t get_bounding_box() override
    {
        return wall->output->get_layout_geometry();
    }

  private:
    expo_fix_wall_t *wall;
    std::vector<std::vector<std::shared_ptr<workspace_stream_node_t>>> workspaces;

    // Buffers keeping the contents of almost-static workspaces
    per_workspace_map_t<wf::auxilliary_buffer_t> aux_buffers;
    // Damage accumulated for those buffers
    per_workspace_map_t<wf::regionf_t> aux_buffer_damage;

    // Downscaled copies of the workspace buffers, refreshed by blitting from the full-resolution
    // buffer (never by re-rendering the workspace). Compositing samples the copy closest to the
    // on-screen size of the workspace.
    struct scaled_copy_t
    {
        wf::auxilliary_buffer_t buffer;
        wf::regionf_t dirty;
        bool valid = false;
    };
    per_workspace_map_t<std::array<scaled_copy_t, 2>> aux_copies;
    // The copy level chosen for presentation this frame (-1 = full resolution)
    per_workspace_map_t<int> aux_present_level;
    // Current rendering scale for the workspace
    per_workspace_map_t<float> aux_buffer_current_scale;
    // Current subbox for the workspace
    per_workspace_map_t<std::optional<wf::geometry_t>> aux_buffer_current_subbox;
};

expo_fix_wall_t::expo_fix_wall_t(wf::output_t *_output) : output(_output)
{
    this->viewport = get_wall_rectangle();
}

expo_fix_wall_t::~expo_fix_wall_t()
{
    stop_output_renderer(false);
}

void expo_fix_wall_t::set_background_color(const wf::color_t& color)
{
    this->background_color = color;
}

void expo_fix_wall_t::set_gap_size(int size)
{
    this->gap_size = size;
}

void expo_fix_wall_t::set_viewport(const wf::geometry_t& viewport_geometry)
{
    this->viewport = viewport_geometry;
    if (render_node)
    {
        scene::damage_node(
            this->render_node, this->render_node->get_bounding_box());
    }
}

wf::geometry_t expo_fix_wall_t::get_viewport() const
{
    return viewport;
}

void expo_fix_wall_t::set_viewport_animating(bool animating)
{
    this->viewport_animating = animating;
}

void expo_fix_wall_t::render_wall(
    const wf::render_target_t& fb, const wf::regionf_t& damage)
{
    expo_fix_wall_frame_event_t data{fb};
    this->emit(&data);
}

void expo_fix_wall_t::start_output_renderer()
{
    wf::dassert(render_node == nullptr, "Starting workspace-wall twice?");
    render_node = std::make_shared<workspace_wall_node_t>(this);
    scene::add_front(wf::get_core().scene(), render_node);
}

void expo_fix_wall_t::stop_output_renderer(bool reset_viewport)
{
    if (!render_node)
    {
        return;
    }

    scene::remove_child(render_node);
    render_node = nullptr;

    if (reset_viewport)
    {
        set_viewport({0, 0, 0, 0});
    }
}

wf::geometry_t expo_fix_wall_t::get_workspace_rectangle(
    const wf::point_t& ws) const
{
    auto size = this->output->get_screen_size();

    return {(double)(ws.x * (size.width + gap_size)), (double)(ws.y * (size.height + gap_size)),
        (double)size.width, (double)size.height};
}

wf::geometry_t expo_fix_wall_t::get_wall_rectangle() const
{
    auto size = this->output->get_screen_size();
    auto workspace_size = this->output->wset()->get_workspace_grid_size();

    return {(double)-gap_size, (double)-gap_size,
        (double)(workspace_size.width * (size.width + gap_size) + gap_size),
        (double)(workspace_size.height * (size.height + gap_size) + gap_size)};
}

void expo_fix_wall_t::set_ws_dim(const wf::point_t& ws, float value)
{
    render_colors[{ws.x, ws.y}] = value;
    if (render_node)
    {
        scene::damage_node(render_node, render_node->get_bounding_box());
    }
}

float expo_fix_wall_t::get_color_for_workspace(wf::point_t ws)
{
    auto it = render_colors.find({ws.x, ws.y});
    if (it == render_colors.end())
    {
        return 1.0;
    }

    return it->second;
}

std::vector<wf::point_t> expo_fix_wall_t::get_visible_workspaces(
    wf::geometry_t viewport) const
{
    std::vector<wf::point_t> visible;
    auto wsize = output->wset()->get_workspace_grid_size();
    for (int i = 0; i < wsize.width; i++)
    {
        for (int j = 0; j < wsize.height; j++)
        {
            if (viewport & get_workspace_rectangle({i, j}))
            {
                visible.push_back({i, j});
            }
        }
    }

    return visible;
}
} // namespace wf
