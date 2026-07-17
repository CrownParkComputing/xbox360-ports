# qrenderdoc --python-script rd_analyze.py  (RD_CAPTURE and RD_OUT env vars)
# Dumps: action list with render targets, every RT-flagged texture, and every
# cube texture (all faces) — to find garbage reflection cubemaps.
import os
import traceback

out_dir = os.environ.get("RD_OUT", "/tmp")
os.makedirs(out_dir, exist_ok=True)
prog = open(os.path.join(out_dir, "progress.txt"), "w")


def p(msg):
    prog.write(str(msg) + "\n")
    prog.flush()


try:
    p("script start")
    import renderdoc as rd

    p("renderdoc module imported")
    capture_path = os.environ.get("RD_CAPTURE")
    p("capture: %s" % capture_path)

    cap = rd.OpenCaptureFile()
    res = cap.OpenFile(capture_path, "", None)
    p("OpenFile -> %s" % res)

    res, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    p("OpenCapture -> %s" % res)

    textures = {t.resourceId: t for t in controller.GetTextures()}
    p("textures: %d" % len(textures))

    lines = []

    def walk(actions, depth=0):
        for a in actions:
            try:
                name = a.GetName(controller.GetStructuredFile())
            except Exception:
                name = "?"
            flags = a.flags
            if flags & (rd.ActionFlags.Drawcall | rd.ActionFlags.Dispatch |
                        rd.ActionFlags.Clear | rd.ActionFlags.Copy |
                        rd.ActionFlags.Resolve):
                outs = []
                try:
                    outs = [str(o.resource) for o in a.outputs
                            if o.resource != rd.ResourceId.Null()]
                except Exception:
                    pass
                lines.append("%s[%d] %s outs=%s" % ("  " * depth, a.eventId, name, outs))
            if a.children:
                walk(a.children, depth + 1)

    walk(controller.GetRootActions())
    p("actions walked: %d lines" % len(lines))
    with open(os.path.join(out_dir, "actions.txt"), "w") as f:
        f.write("\n".join(lines))

    saved = 0
    for rid, tex in textures.items():
        is_cube = bool(tex.cubemap)
        is_rt = bool(tex.creationFlags & (rd.TextureCategory.ColorTarget |
                                          rd.TextureCategory.DepthTarget))
        if not (is_cube or is_rt):
            continue
        kind = "cube" if is_cube else "rt"
        slices = tex.arraysize if is_cube else 1
        for s in range(slices):
            st = rd.TextureSave()
            st.resourceId = rid
            st.mip = 0
            st.slice.sliceIndex = s
            st.alpha = rd.AlphaMapping.Discard
            st.destType = rd.FileType.PNG
            fn = os.path.join(out_dir, "%s_%s_%dx%d_s%d.png" %
                              (kind, str(rid).replace("::", "_").replace(" ", ""),
                               tex.width, tex.height, s))
            try:
                ok = controller.SaveTexture(st, fn)
                if ok:
                    saved += 1
            except Exception as e:
                p("SaveTexture failed %s: %s" % (fn, e))
        p("tex %s %s %dx%d arr=%d cube=%s" %
          (str(rid), kind, tex.width, tex.height, tex.arraysize, is_cube))
    p("saved %d images" % saved)

    controller.Shutdown()
    cap.Shutdown()
    p("done")
except Exception:
    p("EXCEPTION:\n" + traceback.format_exc())
finally:
    prog.close()
