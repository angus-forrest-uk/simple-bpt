{ config, lib, pkgs, ... }:

let
  cfg = config.services.simple-bpt;
in
{
  options.services.simple-bpt = {
    enable = lib.mkEnableOption "simple-bpt";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.simple-bpt;
      defaultText = lib.literalExpression "pkgs.simple-bpt";
      description = "Package to run.";
    };

    bind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "100.64.0.2";
      description = ''
        Address to bind. BPT has no authentication.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 46729;
      description = "Port to listen on.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/simple-bpt";
      description = "Holds the database under `HMRC/payetools-rti`.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open {option}`port` in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "services.simple-bpt: BPT is x86_64-linux only.";
      }
      {
        assertion = !(cfg.openFirewall && cfg.bind == "0.0.0.0");
        message = ''
          services.simple-bpt: openFirewall with bind = "0.0.0.0" exposes an
          unauthenticated payroll application on every interface.
        '';
      }
    ];

    warnings = lib.optional (cfg.bind != "127.0.0.1" && cfg.bind != "::1") ''
      services.simple-bpt is bound to ${cfg.bind}, which sets ALLOWED_HOSTS to
      ['*']. BPT has no authentication.
    '';

    users.users.simple-bpt = {
      isSystemUser = true;
      group = "simple-bpt";
      home = cfg.stateDir;
    };
    users.groups.simple-bpt = { };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.simple-bpt = {
      description = "Basic PAYE Tools (headless)";
      documentation = [
        "https://github.com/angus-forrest-uk/simple-bpt"
        "https://www.gov.uk/basic-paye-tools"
      ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOME = cfg.stateDir;
        BPT_STATE_DIR = cfg.stateDir;
        BPT_BIND = cfg.bind;
        BPT_PORT = toString cfg.port;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        User = "simple-bpt";
        Group = "simple-bpt";
        StateDirectory = "simple-bpt";
        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RemoveIPC = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        SystemCallFilter = [ "@system-service" ];
        SystemCallErrorNumber = "EPERM";
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ "" ];
      };
    };
  };
}
