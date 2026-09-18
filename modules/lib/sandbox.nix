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
  };
}
