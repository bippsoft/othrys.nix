# modules/lib/sandbox.nix
# One systemd sandboxing baseline for the units othrys defines itself
{
  # What a unit needs when it holds no privilege, touches no device and writes
  # nowhere outside the directories systemd hands it. A unit merges this into
  # its serviceConfig and then states its own exceptions beside it, so the
  # exceptions are what a reader sees. Left to each unit on purpose are the
  # user (DynamicUser, or root for a unit that reads a root-owned secret) and
  # RestrictAddressFamilies, since no single value suits both a unit that
  # talks to the network and one that must not.
  baseline = {
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
    CapabilityBoundingSet = [""];
    AmbientCapabilities = [""];
    NoNewPrivileges = true;

    # Each of these costs a unit nothing it is entitled to. The clock, the
    # host name and the kernel log are read-only or hidden, other processes
    # are invisible under /proc and only the process entries are mounted,
    # mount changes stay inside the unit, System V objects go with it, and
    # files it creates are private to it. PrivateUsers and IPAddressDeny
    # stay with the unit, since the first breaks a unit that keeps a
    # capability and the second one that talks to the network.
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    PrivateMounts = true;
    RemoveIPC = true;
    UMask = "0077";
  };
}
