# qrenderdoc --python rd_chain.py — list all copy/resolve/dispatch actions with
# sources/destinations, to trace how the final 1024x600 image gets its content.
import os
import traceback

out_dir = os.environ.get("RD_OUT", "/tmp")
prog = open(os.path.join(out_dir, "chain_progress.txt"), "w")


def p(msg):
    prog.write(str(msg) + "\n")
    prog.flush()


try:
    import renderdoc as rd

    cap = rd.OpenCaptureFile()
    cap.OpenFile(os.environ.get("RD_CAPTURE"), "", None)
    res, controller = cap.OpenCapture(rd.ReplayOptions(), None)
    p("OpenCapture -> %s" % res)
    sdfile = controller.GetStructuredFile()

    lines = []

    def walk(actions, depth=0):
        for a in actions:
            f = a.flags
            if f & (rd.ActionFlags.Copy | rd.ActionFlags.Resolve | rd.ActionFlags.Clear):
                lines.append("[%d] %s  src=%s dst=%s" %
                             (a.eventId, a.GetName(sdfile), a.copySource, a.copyDestination))
            elif f & rd.ActionFlags.Dispatch:
                lines.append("[%d] %s  DISPATCH %sx%sx%s" %
                             (a.eventId, a.GetName(sdfile),
                              a.dispatchDimension[0], a.dispatchDimension[1],
                              a.dispatchDimension[2]))
            if a.children:
                walk(a.children, depth + 1)

    walk(controller.GetRootActions())
    with open(os.path.join(out_dir, "chain.txt"), "w") as fo:
        fo.write("\n".join(lines))
    p("wrote %d chain lines" % len(lines))

    # For each dispatch after eid 10000, record bound compute images/buffers.
    for a_line in lines[-40:]:
        p(a_line)

    controller.Shutdown()
    cap.Shutdown()
    p("done")
except Exception:
    p("EXCEPTION:\n" + traceback.format_exc())
finally:
    prog.close()
