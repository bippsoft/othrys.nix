# modules/hardware/graphics/default.nix
# Graphics module aggregator (NVIDIA, PRIME, shader cache)
{
  imports = [
    ./nvidia.nix
    ./prime.nix
    ./shader-cache.nix
  ];
}
