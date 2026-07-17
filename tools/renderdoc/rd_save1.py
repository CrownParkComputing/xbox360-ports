# qrenderdoc --python rd_save1.py — save specific textures listed in RD_IDS.
import os
import traceback

out_dir = os.environ.get("RD_OUT", "/tmp")
prog = open(os.path.join(out_dir, "save1_progress.txt"), "w")


def p(msg):
    prog.write(str(msg) + "\n")
    prog.flush()


try:
    import renderdoc as rd

    cap = rd.OpenCaptureFile()
    cap.OpenFile(os.environ.get("RD_CAPTURE"), "", None)
    res, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    p("OpenCapture -> %s" % res)

    want = set(os.environ.get("RD_IDS", "").split(","))
    n = 0
    for t in controller.GetTextures():
        rid_num = str(t.resourceId).split("::")[-1]
        if rid_num not in want:
            continue
        st = rd.TextureSave()
        st.resourceId = t.resourceId
        st.mip = 0
        st.alpha = rd.AlphaMapping.Discard
        st.destType = rd.FileType.PNG
        fn = os.path.join(out_dir, "tex_%s_%dx%d.png" % (rid_num, t.width, t.height))
        ok = controller.SaveTexture(st, fn)
        p("save %s -> %s (%s)" % (t.resourceId, fn, ok))
        n += 1
    p("saved %d" % n)
    controller.Shutdown()
    cap.Shutdown()
    p("done")
except Exception:
    p("EXCEPTION:\n" + traceback.format_exc())
finally:
    prog.close()
