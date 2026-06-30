executable('hide-cursor-once', ['main.c'],
    install: true)

libevdev = dependency('libevdev')

executable('inject-key', ['inject-key.c'],
    dependencies: [libevdev],
    install: true)
