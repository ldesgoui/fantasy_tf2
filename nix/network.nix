# network.nix
#
# https://nixos.org/nixops/manual
# https://nixos.org/nixos/manual

{
  network.description = "Fantasy TF2 container";

  server = { config, lib, pkgs, ... }: {
    deployment.targetEnv = "container";

    imports = [
      <nixpkgs/nixos/modules/profiles/headless.nix>
      <nixpkgs/nixos/modules/profiles/minimal.nix>
    ];
    nixpkgs.pkgs = import ./nixpkgs.nix;
    services.journald.extraConfig = ''MaxRetentionSec=1month'';
    system.stateVersion = "18.03";
    time.timeZone = "UTC";
    programs.bash.enableCompletion = true;
    environment.systemPackages = [ pkgs.rxvt_unicode.terminfo ];
    networking.firewall.allowedTCPPorts = [ 80 5432 ];

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      package = pkgs.nginxMainline;
      commonHttpConfig = ''
        gzip_types application/vnd.pgrst.object+json;
        proxy_buffer_size   128k;
        proxy_buffers   4 256k;
        proxy_busy_buffers_size   256k;
      '';
      virtualHosts.localhost.locations = {
        "/api/".extraConfig = ''
          default_type  application/json;
          proxy_hide_header Content-Location;
          add_header Content-Location  /api/$upstream_http_content_location;
          proxy_set_header  Connection "";
          proxy_http_version 1.1;
          proxy_pass http://localhost:3000/;
        '';
      };
    };

    systemd.services.postgrest =
    let
      config = pkgs.writeText "postgrest.conf" ''
        db-uri = "postgres://postgres@localhost/postgres"
        db-schema = "public"
        db-anon-role = "postgres"
        db-pool = 10
        jwt-secret = "7xgyYx4f5jKJPoCfVSzrJ5U1CRlLN4xHx"
        secret-is-base64 = false
        max-rows = 100
        server-host = "*4"
        server-port = 3000
      '';
    in {
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ];
      script = "${pkgs.postgrest}/bin/postgrest ${config}";
      serviceConfig = {
        Restart = "always";
        RestartSec = "3";
      };
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql100;
      extraConfig = ''
        listen_addresses = '*'
        shared_buffers = 512MB
        work_mem = 100MB # raise if temp files are getting created
        maintenance_work_mem = 128MB
        effective_io_concurrency = 200 # could be wrong, depends on provider
        max_worker_processes = 4
        max_parallel_workers_per_gather = 2
        max_parallel_workers = 4

        wal_buffers = 16MB
        checkpoint_completion_target = 0.9
        max_wal_size = 8GB
        min_wal_size = 4GB

        random_page_cost = 1.1
        effective_cache_size = 3GB
        default_statistics_target = 100 # raise if planner starts sucking

        log_destination = syslog
        log_connections = true
        log_disconnections = true
        log_line_prefix = 'pid=%p '
        log_statement = all
        log_temp_files = 0MB
        log_lock_waits = true
        log_checkpoints = true
        log_replication_commands = true
        log_timezone = UTC

        track_io_timing = true
        track_functions = all

        log_autovacuum_min_duration = 0
        autovacuum_vacuum_threshold = 10000
        autovacuum_vacuum_scale_factor = 0
        autovacuum_vacuum_cost_limit = 1000

        timezone = UTC
        shared_preload_libraries = 'auto_explain,pg_stat_statements'

        auto_explain.log_min_duration = 100ms
        auto_explain.log_analyze = true
        auto_explain.log_verbose = true
        auto_explain.log_buffers = true
        auto_explain.log_nested_statements = true
        auto_explain.log_timing = true
        auto_explain.log_triggers = true
        auto_explain.log_format = yaml

        pg_stat_statements.max = 10000
        pg_stat_statements.save = true
        pg_stat_statements.track = all
        pg_stat_statements.track_utiliy = true
      '';
      authentication = lib.mkForce ''
        local all all trust
        host all all all trust
      '';
    };
  };
}
