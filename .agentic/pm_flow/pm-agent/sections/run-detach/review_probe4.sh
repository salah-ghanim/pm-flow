#!/bin/zsh -f
# Does the os.setsid() spawn survive when `start` is typed at an INTERACTIVE
# shell (job control on)? If zsh makes the script a process-group leader and
# python3 inherited that group, setsid() would fail with EPERM.
inner=/tmp/pm-flow-setsid-probe.$$.zsh
out=/tmp/pm-flow-setsid-probe.$$.out
cat > "$inner" <<'EOF'
python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  python3 -c 'import os,sys; sys.stderr.write("child pid=%d pgid=%d sid=%d\n" % (os.getpid(), os.getpgrp(), os.getsid(0)))' \
  >> "$1" 2>&1 &!
print -r -- "script pid=$$ pgid=$(python3 -c 'import os; print(os.getpgrp())') spawned=$!"
EOF
print -r -- "--- non-interactive parent ---"
zsh -f "$inner" "$out"
/bin/sleep 1
print -r -- "--- interactive parent (job control on) ---"
zsh -i -f -c "zsh -f $inner $out" 2>/dev/null
/bin/sleep 1
print -r -- "--- child observations ---"
/bin/cat "$out"
rm -f -- "$inner" "$out"
