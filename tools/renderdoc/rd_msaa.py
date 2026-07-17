import os, traceback
out_dir = os.environ.get("RD_OUT", "/tmp")
prog = open(os.path.join(out_dir, "msaa_progress.txt"), "w")
def p(m):
    prog.write(str(m) + "\n"); prog.flush()
try:
    import renderdoc as rd
    cap = rd.OpenCaptureFile()
    cap.OpenFile(os.environ.get("RD_CAPTURE"), "", None)
    res, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    p("open %s" % res)
    controller.SetFrameEvent(int(os.environ.get("RD_EID", "10931")), True)
    for t in controller.GetTextures():
        if str(t.resourceId).endswith("242929"):
            for s in (0, 1):
                st = rd.TextureSave()
                st.resourceId = t.resourceId
                st.mip = 0
                st.sample.sampleIndex = s
                st.alpha = rd.AlphaMapping.Discard
                st.destType = rd.FileType.PNG
                fn = os.path.join(out_dir, "scene_s%d.png" % s)
                ok = controller.SaveTexture(st, fn)
                p("sample %d -> %s" % (s, ok))
    controller.Shutdown(); cap.Shutdown(); p("done")
except Exception:
    p("EXC:\n" + traceback.format_exc())
finally:
    prog.close()
