# The settings dmgbuild reads for Peel's disk image. Scripts/make_dmg.sh passes every value with -D.
import os.path

app = defines["app"]
width, height = int(defines["width"]), int(defines["height"])
icons_y = int(defines["icons_y"])

format = "ULFO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "Peel.icns")
hide_extensions = [os.path.basename(app)]
background = defines["background"]
window_rect = ((200, 200), (width, height))
default_view = "icon-view"
show_icon_preview = False
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (int(defines["peel_x"]), icons_y),
    "Applications": (int(defines["applications_x"]), icons_y),
}
