# modules/system/shell/starship.nix
# Starship prompt with bracketed segments, coloured from the theme palette
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.shell.starship;
  theme = config.othrys.theme;

  # A palette colour where the host has a palette, and otherwise the ANSI
  # name in the same position, which the terminal resolves with its own
  # colours. The layout is the same either way.
  colour = base: ansi:
    if theme.palette != null
    then theme.colors.withHashtag.${base}
    else ansi;
in {
  options.othrys.system.shell.starship = {
    enable = lib.mkEnableOption "Starship prompt";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."system.shell.starship".programs.starship = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;

      settings = {
        "$schema" = "https://starship.rs/config-schema.json";

        # Time on right side
        right_format = "$time";
        time = {
          disabled = false;
          format = "\\[[$time]($style)\\]";
          time_format = "%I:%M %p";
          # The default foreground has no ANSI name that reads on both a dark
          # and a light terminal, so without a palette the time is left unstyled.
          style = colour "base05" "none";
        };

        # Bracketed segments format
        aws.format = "\\[[($symbol($profile)(\\($region\\))(\\[$duration\\]))]($style)\\]";
        azure.format = "\\[[$symbol($subscription)]($style)\\]";
        battery.format = "\\[[$symbol$percentage]($style)\\]";
        buf.format = "\\[[$symbol($version)]($style)\\]";
        bun.format = "\\[[$symbol($version)]($style)\\]";
        c.format = "\\[[$symbol($version(-$name))]($style)\\]";
        cmake.format = "\\[[$symbol($version)]($style)\\]";
        cmd_duration.format = "\\[[took $duration]($style)\\]";
        cobol.format = "\\[[$symbol($version)]($style)\\]";
        conda.format = "\\[[$symbol$environment]($style)\\]";
        container.format = "\\[[$symbol \\[$name\\]]($style)\\]";
        cpp.format = "\\[[$symbol($version(-$name))]($style)\\]";
        crystal.format = "\\[[$symbol($version)]($style)\\]";
        daml.format = "\\[[$symbol($version)]($style)\\]";
        dart.format = "\\[[$symbol($version)]($style)\\]";
        deno.format = "\\[[$symbol($version)]($style)\\]";
        direnv.format = "\\[[$symbol$loaded/$allowed]($style)\\]";
        docker_context.format = "\\[[$symbol$context]($style)\\]";
        dotnet.format = "\\[[$symbol($version)(🎯 $tfm)]($style)\\]";
        elixir.format = "\\[[$symbol($version \\(OTP $otp_version\\))]($style)\\]";
        elm.format = "\\[[$symbol($version)]($style)\\]";
        erlang.format = "\\[[$symbol($version)]($style)\\]";
        fennel.format = "\\[[$symbol($version)]($style)\\]";
        fortran.format = "\\[[$symbol($version)]($style)\\]";
        fossil_branch.format = "\\[[$symbol$branch]($style)\\]";
        fossil_metrics.format = "\\[[+$added]($added_style)\\]\\[[-$deleted]($deleted_style)\\]";
        gcloud.format = "\\[[$symbol$account(@$domain)(\\($region\\))]($style)\\]";
        git_branch.format = "\\[[$symbol$branch]($style)\\]";
        git_commit.format = "\\[[\\($hash$tag\\)]($style)\\]";
        git_metrics.format = "\\[[+$added]($added_style)\\]\\[[-$deleted]($deleted_style)\\]";
        git_state.format = "\\[[$state ($progress_current/$progress_total)]($style)\\]";
        git_status.format = "([\\[$all_status$ahead_behind\\]]($style))";
        gleam.format = "\\[[$symbol($version)]($style)\\]";
        golang.format = "\\[[$symbol($version)]($style)\\]";
        gradle.format = "\\[[$symbol($version)]($style)\\]";
        guix_shell.format = "\\[[$symbol]($style)\\]";
        haskell.format = "\\[[$symbol($version)]($style)\\]";
        haxe.format = "\\[[$symbol($version)]($style)\\]";
        helm.format = "\\[[$symbol($version)]($style)\\]";
        hg_branch.format = "\\[[$symbol$branch]($style)\\]";
        hostname.format = "\\[[$ssh_symbol$hostname]($style)\\]";
        java.format = "\\[[$symbol($version)]($style)\\]";
        jobs.format = "\\[[$symbol$number]($style)\\]";
        julia.format = "\\[[$symbol($version)]($style)\\]";
        kotlin.format = "\\[[$symbol($version)]($style)\\]";
        kubernetes.format = "\\[[$symbol$context( \\($namespace\\))]($style)\\]";
        localip.format = "\\[[$localipv4]($style)\\]";
        lua.format = "\\[[$symbol($version)]($style)\\]";
        memory_usage.format = "\\[$symbol[$ram( | $swap)]($style)\\]";
        meson.format = "\\[[$symbol$project]($style)\\]";
        nim.format = "\\[[$symbol($version)]($style)\\]";
        nix_shell.format = "\\[[$symbol$name( ($state))]($style)\\]";
        nodejs.format = "\\[[$symbol($version)]($style)\\]";
        ocaml.format = "\\[[$symbol($version)(\\($switch_indicator$switch_name\\))]($style)\\]";
        opa.format = "\\[[$symbol($version)]($style)\\]";
        openstack.format = "\\[[$symbol$cloud(\\($project\\))]($style)\\]";
        os.format = "\\[[$symbol]($style)\\]";
        package.format = "\\[[$symbol$version]($style)\\]";
        perl.format = "\\[[$symbol($version)]($style)\\]";
        php.format = "\\[[$symbol($version)]($style)\\]";
        pijul_channel.format = "\\[[$symbol$channel]($style)\\]";
        pixi.format = "\\[[$symbol$version( $environment)]($style)\\]";
        pulumi.format = "\\[[$symbol$stack]($style)\\]";
        purescript.format = "\\[[$symbol($version)]($style)\\]";
        python.format = "\\[[$symbol$pyenv_prefix($version)(\\($virtualenv\\))]($style)\\]";
        raku.format = "\\[[$symbol($version-$vm_version)]($style)\\]";
        red.format = "\\[[$symbol($version)]($style)\\]";
        rlang.format = "\\[[$symbol($version)]($style)\\]";
        ruby.format = "\\[[$symbol($version)]($style)\\]";
        rust.format = "\\[[$symbol($version)]($style)\\]";
        scala.format = "\\[[$symbol($version)]($style)\\]";
        shell.format = "\\[[$indicator]($style)\\]";
        singularity.format = "\\[[$symbol\\[$env\\]]($style)\\]";
        solidity.format = "\\[[$symbol($version)]($style)\\]";
        spack.format = "\\[[$symbol$environment]($style)\\]";
        status.format = "\\[[$symbol$status]($style)\\]";
        sudo.format = "\\[[as $symbol]($style)\\]";
        swift.format = "\\[[$symbol($version)]($style)\\]";
        terraform.format = "\\[[$symbol$workspace]($style)\\]";
        username.format = "\\[[$user]($style)\\]";
        vagrant.format = "\\[[$symbol($version)]($style)\\]";
        vcsh.format = "\\[[vcsh $repo]($style)\\]";
        vlang.format = "\\[[$symbol($version)]($style)\\]";
        xmake.format = "\\[[$symbol($version)]($style)\\]";
        zig.format = "\\[[$symbol($version)]($style)\\]";

        # Colours
        directory.style = colour "base0D" "blue";
        git_branch.style = colour "base0B" "green";
        git_status.style = colour "base0A" "yellow";
        git_metrics = {
          added_style = colour "base0B" "green";
          deleted_style = colour "base08" "red";
        };
        username.style_user = colour "base0D" "blue";
        username.style_root = colour "base08" "red";
        hostname.style = colour "base0E" "purple";
        cmd_duration.style = colour "base0A" "yellow";
        nix_shell = {
          symbol = "󱄅 ";
          style = colour "base0C" "cyan";
          impure_msg = "";
          pure_msg = "pure";
        };
        golang = {
          symbol = " ";
        };
        character = {
          success_symbol = "[❯](bold ${colour "base0B" "green"})";
          error_symbol = "[❯](bold ${colour "base08" "red"})";
          vimcmd_symbol = "[❮](bold ${colour "base0B" "green"})";
        };
      };
    };
  };
}
