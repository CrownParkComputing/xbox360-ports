# qrenderdoc --python rd_draws.py — dump PS textures + disasm for given draws.
import os
import traceback

out_dir = os.environ.get("RD_OUT", "/tmp")
prog = open(os.path.join(out_dir, "draws_progress.txt"), "w")


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

    eids = [int(e) for e in os.environ.get("RD_EIDS", "9707,9806,10043").split(",")]
    for eid in eids:
        controller.SetFrameEvent(eid, True)
        pipe = controller.GetPipelineState()
        p("=== eid %d ===" % eid)
        try:
            ro = pipe.GetReadOnlyResources(rd.ShaderStage.Pixel)
            for i, u in enumerate(ro):
                rid = u.descriptor.resource
                if rid == rd.ResourceId.Null():
                    continue
                t = textures.get(rid)
                desc = ("%dx%d arr=%d ms=%d cube=%s fmt=%s" %
                        (t.width, t.height, t.arraysize, t.msSamp, t.cubemap,
                         t.format.Name())) if t else "buffer"
                p("  PS RO[%d]: %s %s" % (i, rid, desc))
        except Exception as e:
            p("  ro err %s" % e)
        try:
            blends = pipe.GetColorBlends()
            b = blends[0]
            p("  blend: en=%s src=%s dst=%s op=%s" %
              (b.enabled, b.colorBlend.source, b.colorBlend.destination,
               b.colorBlend.operation))
        except Exception as e:
            p("  blend err %s" % e)
        try:
            ps = pipe.GetShaderReflection(rd.ShaderStage.Pixel)
            if ps:
                pobj = pipe.GetGraphicsPipelineObject()
                dis = controller.DisassembleShader(pobj, ps, "")
                fn = os.path.join(out_dir, "ps_%d.txt" % eid)
                with open(fn, "w") as f:
                    f.write(dis)
                p("  PS disasm %d chars -> %s" % (len(dis), fn))
        except Exception as e:
            p("  disasm err %s" % e)

    controller.Shutdown()
    cap.Shutdown()
    p("done")
except Exception:
    p("EXC:\n" + traceback.format_exc())
finally:
    prog.close()
