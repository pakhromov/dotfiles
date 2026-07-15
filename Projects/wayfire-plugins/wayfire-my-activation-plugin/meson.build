project(
	'wayfire-my-activation',
	['c', 'cpp'],
	version: '0.1.0',
	license: 'MIT',
	meson_version: '>=0.51.0',
	default_options: [
		'cpp_std=c++17',
	],
)

wayfire = dependency('wayfire')

add_project_arguments(['-DWLR_USE_UNSTABLE'], language: 'cpp')

subdir('metadata')
subdir('src')
