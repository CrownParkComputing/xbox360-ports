# qrenderdoc --python rd_dispatch.py — inspect compute bindings of the final
# resolve dispatches to map source->dest and find where confetti enters.
import os
import traceback

out_dir = os.environ.get("RD_OUT", "/tmp")
prog = open(os.path.join(out_dir, "dispatch_progress.txt"), "w")


def p(msg):
    prog.write(str(msg) + "\n")
    prog.flush()


try:
    import renderdoc as rd

    cap = rd.OpenCaptureFile()
    cap.OpenFile(os.environ.get("RD_CAPTURE"), "", None)
    res, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    p("OpenCapture -> %s" % res)

    textures = {t.resourceId: t for t in controller.GetTextures()}

    for eid in (10932, 10937, 10950, 10957):
        controller.SetFrameEvent(eid, True)
        pipe = controller.GetPipelineState()
        p("=== dispatch eid %d ===" % eid)
        try:
            ro = pipe.GetReadOnlyResources(rd.ShaderStage.Compute)
            for i, arr in enumerate(ro):
                for r in [arr]:
                    if r.descriptor.resource != rd.ResourceId.Null():
                        t = textures.get(r.descriptor.resource)
                        desc = ("%dx%d ms=%d fmt=%s" % (t.width, t.height, t.msSamp,
                                t.format.Name())) if t else "buffer"
                        p("  RO[%d]: %s %s" % (i, r.descriptor.resource, desc))
        except Exception as e:
            p("  ro err %s" % e)
        try:
            rw = pipe.GetReadWriteResources(rd.ShaderStage.Compute)
            for i, arr in enumerate(rw):
                for r in [arr]:
                    if r.descriptor.resource != rd.ResourceId.Null():
                        t = textures.get(r.descriptor.resource)
                        desc = ("%dx%d ms=%d fmt=%s" % (t.width, t.height, t.msSamp,
                                t.format.Name())) if t else "buffer"
                        p("  RW[%d]: %s %s" % (i, r.descriptor.resource, desc))
        except Exception as e:
            p("  rw err %s" % e)

    controller.Shutdown()
    cap.Shutdown()
    p("done")
except Exception:
    p("EXCEPTION:\n" + traceback.format_exc())
finally:
    prog.close()
