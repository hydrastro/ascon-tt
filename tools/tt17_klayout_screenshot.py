import pya
lv = pya.LayoutView()
lv.load_layout(in_gds, 0)
lv.max_hier()
lv.zoom_fit()
lv.save_image(out_png, 1800, 1400)
