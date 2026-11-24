# Configuración de dmgbuild. build.sh la invoca con:  -D app=<ruta absoluta del .app> -D bg=<ruta absoluta de background.tiff>
import os.path

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}   # arrastrar y soltar; el doble clic instala en /Applications
background = defines["bg"]
icon_locations = {os.path.basename(app): (150, 232), "Applications": (370, 232)}
window_rect = ((200, 200), (520, 440))
icon_size = 96
text_size = 12
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
format = "UDZO"
