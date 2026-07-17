# qrenderdoc --python rd_pixel2.py — find the draw target + viewport at a
# mid-scene draw, then pixel-history the disco-glass pixels there.
import os
import traceback

out_dir = os.environ.get("RD_OUT", "/tmp")
os.makedirs(out_dir, exist_ok=True)
prog = open(os.path.join(out_dir, "pixel2_progress.txt"), "w")


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

    # Reference draw in the middle of the scene pass.
    ref_eid = int(os.environ.get("RD_REF_EID", "5441"))
    controller.SetFrameEvent(ref_eid, True)
    pipe = controller.GetPipelineState()
    outs = pipe.GetOutputTargets()
    depth = pipe.GetDepthTarget()
    vps = pipe.GetViewport(0)
    p("ref eid %d: outputs=%s depth=%s" %
      (ref_eid, [str(o.resource) for o in outs], depth.resource))
    p("viewport: x=%.1f y=%.1f w=%.1f h=%.1f" % (vps.x, vps.y, vps.width, vps.height))
    target = None
    for o in outs:
        if o.resource != rd.ResourceId.Null():
            target = o.resource
            break
    t = textures.get(target)
    p("draw target: %s %dx%d fmt=%s msaa=%d" %
      (target, t.width, t.height, t.format.Name(), t.msSamp))

    # Map screen pixels into the RT via the viewport origin.
    base_x, base_y = int(vps.x), int(vps.y)
    sub = rd.Subresource(0, 0, 0)
    pts = [(448, 182), (452, 182), (533, 190)]
    hits = {}
    for (sx, sy) in pts:
        x, y = base_x + sx, base_y + sy
        mods = controller.PixelHistory(target, x, y, sub, rd.CompType.Typeless)
        p("--- rt pixel (%d,%d): %d mods" % (x, y, len(mods)))
        for m in mods:
            col = m.shaderOut.col.floatValue
            post = m.postMod.col.floatValue
            p("  eid=%d passed=%s out=(%.3f,%.3f,%.3f,%.3f) post=(%.3f,%.3f,%.3f,%.3f)"
              % (m.eventId, m.Passed(), col[0], col[1], col[2], col[3],
                 post[0], post[1], post[2], post[3]))
            if m.Passed():
                hits.setdefault(m.eventId, 0)
                hits[m.eventId] += 1
    p("writer eids: %s" % sorted(hits))

    with open(os.path.join(out_dir, "writers.txt"), "w") as f:
        f.write("\n".join(str(e) for e in sorted(hits)))

    controller.Shutdown()
    cap.Shutdown()
    p("done")
except Exception:
    p("EXCEPTION:\n" + traceback.format_exc())
finally:
    prog.close()
