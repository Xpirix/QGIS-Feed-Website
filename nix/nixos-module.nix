# NixOS module for the QGIS Feed Django application.
#
# Deploys the Django instance only. PostgreSQL and Metabase are provided by the
# surrounding infrastructure, so this module deliberately does not configure a
# database server; it only points Django at one.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.qgisfeed;

  # Non-secret configuration. Secrets must never appear here: everything in the
  # systemd unit ends up in the world-readable Nix store.
  environment = {
    DJANGO_SETTINGS_MODULE = cfg.settingsModule;
    QGISFEED_ALLOWED_HOSTS = lib.concatStringsSep "," cfg.allowedHosts;
    QGIS_FEED_PROD_URL = cfg.domain;
    QGISFEED_DOCKER_DBNAME = cfg.database.name;
    QGISFEED_DOCKER_DBUSER = cfg.database.user;
    QGISFEED_DOCKER_DBHOST = cfg.database.host;
    QGISFEED_DOCKER_DBPORT = toString cfg.database.port;
    QGISFEED_GUNICORN_WORKERS = toString cfg.workers;
    GEOIP_PATH = cfg.geoipPath;
    # PYTHONPATH is set by the package's own wrappers; setting it here as well
    # would only risk the two disagreeing.
  }
  // cfg.extraEnvironment;
in
{
  options.services.qgisfeed = {
    enable = lib.mkEnableOption "the QGIS Feed Django application";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.qgisfeed;
      defaultText = lib.literalExpression "qgisfeed.packages.\${system}.qgisfeed";
      description = "The qgisfeed package to run.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "feed.qgis.org";
      description = ''
        Public hostname. Used for CSRF_TRUSTED_ORIGINS and, unless
        {option}`services.qgisfeed.allowedHosts` is set, for ALLOWED_HOSTS.
      '';
    };

    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ cfg.domain ];
      defaultText = lib.literalExpression "[ config.services.qgisfeed.domain ]";
      description = ''
        Django ALLOWED_HOSTS. Deliberately not "*": an over-broad value lets a
        misconfigured proxy be used for host header poisoning.
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address gunicorn binds to. Defaults to loopback on the assumption that a
        reverse proxy terminates TLS in front of it.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Port gunicorn listens on.";
    };

    workers = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = ''
        Number of gunicorn worker processes. The usual guidance is
        (2 * cores) + 1.
      '';
    };

    settingsModule = lib.mkOption {
      type = lib.types.str;
      default = "qgisfeedproject.settings_nix_production";
      description = "Value of DJANGO_SETTINGS_MODULE.";
    };

    geoipPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/qgisfeed/geoip/";
      description = ''
        Directory containing GeoLite2-City.mmdb. The database is MaxMind
        licensed and is not shipped in the package, so it must be provisioned
        separately; the geofence feature degrades to no location without it.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/secrets/qgisfeed.env";
      description = ''
        Path to a file with `KEY=value` lines, read by systemd at start.

        This is the only supported way to pass secrets. It must contain at
        least:

        - `QGISFEED_SECRET_KEY` - Django SECRET_KEY. Must not be the value
          committed in settings.py, which is public.
        - `QGISFEED_DOCKER_DBPASSWORD` - unless the database uses peer
          authentication over a unix socket.

        and typically also `EMAIL_HOST_PASSWORD`, `SENTRY_DSN`,
        `MASTODON_ACCESS_TOKEN`, `BLUESKY_PASSWORD` and `TELEGRAM_BOT_TOKEN`.

        The file is read by systemd as root, so it can be mode 0400 and owned
        by root. Do not put it in the Nix store, which is world readable.
      '';
    };

    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "/run/postgresql";
        description = ''
          Database host. A path is treated by libpq as a unix socket directory,
          which is the default so that a local PostgreSQL needs no password.
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "Database port.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "qgisfeed";
        description = "Database name.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "qgisfeed";
        description = "Database user.";
      };
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        EMAIL_HOST = "smtp.example.org";
      };
      description = ''
        Additional non-secret environment variables. Anything sensitive belongs
        in {option}`services.qgisfeed.environmentFile` instead, because these
        values are written to the Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.qgisfeed = {
      description = "QGIS Feed Django application";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "postgresql.service"
      ];
      wants = [ "network-online.target" ];

      inherit environment;

      serviceConfig = {
        # gunicorn does not implement sd_notify, so Type=notify would stall
        # until systemd's start timeout expired.
        Type = "exec";

        # An unprivileged, per-service user is allocated at runtime. StateDirectory
        # gives us /var/lib/qgisfeed, exported to the unit as $STATE_DIRECTORY,
        # which settings_nix_production.py uses for MEDIA_ROOT and STATIC_ROOT.
        DynamicUser = true;
        User = "qgisfeed";
        Group = "qgisfeed";
        StateDirectory = "qgisfeed";
        StateDirectoryMode = "0750";
        WorkingDirectory = "${cfg.package}/share/qgisfeed";

        EnvironmentFile = cfg.environmentFile;

        ExecStartPre = [
          "${cfg.package}/bin/qgisfeed-manage migrate --noinput"
          "${cfg.package}/bin/qgisfeed-manage collectstatic --noinput"
        ];

        ExecStart = lib.concatStringsSep " " [
          "${cfg.package}/bin/qgisfeed-gunicorn"
          "qgisfeedproject.wsgi:application"
          "--bind ${cfg.listenAddress}:${toString cfg.port}"
          "--workers ${toString cfg.workers}"
          "--timeout 120"
          "--error-logfile -"
          "--access-logfile -"
        ];

        Restart = "on-failure";
        RestartSec = "5s";

        # Hardening. The service is a plain web application: it needs the
        # network, its state directory and nothing else.
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
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        # AF_UNIX is required for the PostgreSQL socket, AF_INET/AF_INET6 for
        # gunicorn and outbound HTTPS to the syndication APIs.
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ "" ];
        UMask = "0027";
      };
    };
  };
}
