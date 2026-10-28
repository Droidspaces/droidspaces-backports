#!/bin/bash
# Usage: probe-kernel.sh <git dir> <rev>
# Prints one line per kernel feature systemd 258 to 262 cares about: "yes" or "no".
# Works on a blobless clone, every probe fetches only the one file it reads.
d=$1; rev=${2:-FETCH_HEAD}
has() { git -C "$d" show "$rev:$1" 2>/dev/null | grep -qE -- "$2" && echo yes || echo no; }
ver=$(git -C "$d" show "$rev:Makefile" | sed -n 2,4p | awk '{print $3}' | paste -sd.)
echo "kernel $ver"
printf "%-28s %s\n" statx                 "$(has fs/stat.c 'SYSCALL_DEFINE5\(statx')"
printf "%-28s %s\n" TIOCGPTPEER           "$(has include/uapi/asm-generic/ioctls.h TIOCGPTPEER)"
printf "%-28s %s\n" NS_GET_NSTYPE         "$(has include/uapi/linux/nsfs.h NS_GET_NSTYPE)"
printf "%-28s %s\n" SO_PEERGROUPS         "$(has include/uapi/asm-generic/socket.h SO_PEERGROUPS)"
printf "%-28s %s\n" cgroup2_nsdelegate    "$(has kernel/cgroup/cgroup.c nsdelegate)"
printf "%-28s %s\n" cgroup2_cpu_controller "$(has kernel/sched/core.c 'cpu_weight_read_u64|cpu\.weight')"
printf "%-28s %s\n" cgroup2_threads       "$(has kernel/cgroup/cgroup.c 'cgroup\.threads')"
printf "%-28s %s\n" cgroup2_freeze        "$(has kernel/cgroup/cgroup.c 'cgroup\.freeze')"
printf "%-28s %s\n" PSI                   "$(has kernel/sched/psi.c psi_)"
printf "%-28s %s\n" pidfd_send_signal     "$(has kernel/signal.c 'pidfd_send_signal')"
printf "%-28s %s\n" CLONE_PIDFD           "$(has include/uapi/linux/sched.h CLONE_PIDFD)"
printf "%-28s %s\n" pidfd_open            "$(has kernel/pid.c 'SYSCALL_DEFINE2\(pidfd_open')"
printf "%-28s %s\n" pidfd_poll            "$(has kernel/fork.c pidfd_poll)"
printf "%-28s %s\n" waitid_P_PIDFD        "$(has include/uapi/linux/wait.h P_PIDFD)"
printf "%-28s %s\n" SO_BINDTOIFINDEX      "$(has include/uapi/asm-generic/socket.h SO_BINDTOIFINDEX)"
printf "%-28s %s\n" new_mount_api_fsopen  "$(has fs/fsopen.c 'SYSCALL_DEFINE2\(fsopen')"
printf "%-28s %s\n" nexthop_RTNLGRP       "$(has include/uapi/linux/rtnetlink.h RTNLGRP_NEXTHOP)"
printf "%-28s %s\n" procfs_hidepid_text   "$(has fs/proc/root.c 'invisible|HIDEPID_INVISIBLE')"
printf "%-28s %s\n" STATX_MNT_ID          "$(has include/uapi/linux/stat.h STATX_MNT_ID)"
printf "%-28s %s\n" STATX_ATTR_MOUNT_ROOT "$(has include/uapi/linux/stat.h STATX_ATTR_MOUNT_ROOT)"
printf "%-28s %s\n" utimensat_AT_EMPTY_PATH "$(has fs/utimes.c AT_EMPTY_PATH)"
printf "%-28s %s\n" faccessat2            "$(has include/uapi/asm-generic/unistd.h __NR_faccessat2)"
printf "%-28s %s\n" close_range           "$(has include/uapi/asm-generic/unistd.h __NR_close_range)"
printf "%-28s %s\n" memory_recursiveprot  "$(has mm/memcontrol.c memory_recursiveprot)"
printf "%-28s %s\n" MS_NOSYMFOLLOW        "$(has include/uapi/linux/mount.h MS_NOSYMFOLLOW)"
printf "%-28s %s\n" CLONE_INTO_CGROUP     "$(has include/uapi/linux/sched.h CLONE_INTO_CGROUP)"
printf "%-28s %s\n" GRND_INSECURE         "$(has include/uapi/linux/random.h GRND_INSECURE)"
printf "%-28s %s\n" selinux_nexthop_rows  "$(has security/selinux/nlmsgtab.c RTM_NEWNEXTHOP)"
