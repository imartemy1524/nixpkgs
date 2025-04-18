{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.locate;
  isMLocate = lib.hasPrefix "mlocate" cfg.package.name;
  isPLocate = lib.hasPrefix "plocate" cfg.package.name;
in
{
  imports = [
    (lib.mkRenamedOptionModule [ "services" "locate" "period" ] [ "services" "locate" "interval" ])
    (lib.mkRenamedOptionModule [ "services" "locate" "locate" ] [ "services" "locate" "package" ])
    (lib.mkRemovedOptionModule [ "services" "locate" "includeStore" ] "Use services.locate.prunePaths")
    (lib.mkRemovedOptionModule [ "services" "locate" "localuser" ]
      "The services.locate.localuser option has been removed because support for findutils locate has been removed."
    )
  ];

  options.services.locate = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        If enabled, NixOS will periodically update the database of
        files used by the {command}`locate` command.
      '';
    };

    package = lib.mkPackageOption pkgs [ "plocate" ] {
      example = "mlocate";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "02:15";
      example = "hourly";
      description = ''
        Update the locate database at this interval. Updates by
        default at 2:15 AM every day.

        The format is described in
        {manpage}`systemd.time(7)`.

        To disable automatic updates, set to `"never"`
        and run {command}`updatedb` manually.
      '';
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra flags to pass to {command}`updatedb`.
      '';
    };

    output = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/locatedb";
      description = ''
        The database file to build.
      '';
    };

    pruneFS = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "afs"
        "anon_inodefs"
        "auto"
        "autofs"
        "bdev"
        "binfmt"
        "binfmt_misc"
        "ceph"
        "cgroup"
        "cgroup2"
        "cifs"
        "coda"
        "configfs"
        "cramfs"
        "cpuset"
        "curlftpfs"
        "debugfs"
        "devfs"
        "devpts"
        "devtmpfs"
        "ecryptfs"
        "eventpollfs"
        "exofs"
        "futexfs"
        "ftpfs"
        "fuse"
        "fusectl"
        "fusesmb"
        "fuse.ceph"
        "fuse.glusterfs"
        "fuse.gvfsd-fuse"
        "fuse.mfs"
        "fuse.rclone"
        "fuse.rozofs"
        "fuse.sshfs"
        "gfs"
        "gfs2"
        "hostfs"
        "hugetlbfs"
        "inotifyfs"
        "iso9660"
        "jffs2"
        "lustre"
        "lustre_lite"
        "misc"
        "mfs"
        "mqueue"
        "ncpfs"
        "nfs"
        "NFS"
        "nfs4"
        "nfsd"
        "nnpfs"
        "ocfs"
        "ocfs2"
        "pipefs"
        "proc"
        "ramfs"
        "rpc_pipefs"
        "securityfs"
        "selinuxfs"
        "sfs"
        "shfs"
        "smbfs"
        "sockfs"
        "spufs"
        "sshfs"
        "subfs"
        "supermount"
        "sysfs"
        "tmpfs"
        "tracefs"
        "ubifs"
        "udev"
        "udf"
        "usbfs"
        "vboxsf"
        "vperfctrfs"
      ];
      description = ''
        Which filesystem types to exclude from indexing
      '';
    };

    prunePaths = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [
        "/tmp"
        "/var/tmp"
        "/var/cache"
        "/var/lock"
        "/var/run"
        "/var/spool"
        "/nix/store"
        "/nix/var/log/nix"
      ];
      description = ''
        Which paths to exclude from indexing
      '';
    };

    pruneNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".bzr"
        ".cache"
        ".git"
        ".hg"
        ".svn"
      ];
      defaultText = lib.literalMD ''
        `[ ".bzr" ".cache" ".git" ".hg" ".svn" ]`, if
        supported by the locate implementation (i.e. mlocate or plocate).
      '';
      description = ''
        Directory components which should exclude paths containing them from indexing
      '';
    };

    pruneBindMounts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether not to index bind mounts
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    users.groups = lib.mkMerge [
      (lib.mkIf isMLocate { mlocate = { }; })
      (lib.mkIf isPLocate { plocate = { }; })
    ];

    security.wrappers =
      let
        common = {
          owner = "root";
          permissions = "u+rx,g+x,o+x";
          setgid = true;
          setuid = false;
        };
        mlocate = lib.mkIf isMLocate {
          group = "mlocate";
          source = "${cfg.package}/bin/locate";
        };
        plocate = lib.mkIf isPLocate {
          group = "plocate";
          source = "${cfg.package}/bin/plocate";
        };
      in
      {
        locate = lib.mkMerge [
          common
          mlocate
          plocate
        ];
        plocate = lib.mkIf isPLocate (
          lib.mkMerge [
            common
            plocate
          ]
        );
      };

    environment = {
      # write /etc/updatedb.conf for manual calls to `updatedb`
      etc."updatedb.conf".text = ''
        PRUNEFS="${lib.concatStringsSep " " cfg.pruneFS}"
        PRUNENAMES="${lib.concatStringsSep " " cfg.pruneNames}"
        PRUNEPATHS="${lib.concatStringsSep " " cfg.prunePaths}"
        PRUNE_BIND_MOUNTS="${if cfg.pruneBindMounts then "yes" else "no"}"
      '';

      systemPackages = [ cfg.package ];
    };

    systemd.services.update-locatedb = {
      description = "Update Locate Database";

      # mlocate's updatedb takes flags via a configuration file or
      # on the command line, but not by environment variable.
      script =
        let
          toFlags =
            x: lib.optional (cfg.${x} != [ ]) "--${lib.toLower x} '${lib.concatStringsSep " " cfg.${x}}'";
          args = lib.concatLists (
            map toFlags [
              "pruneFS"
              "pruneNames"
              "prunePaths"
            ]
          );
        in
        ''
          exec ${cfg.package}/bin/updatedb \
            --output ${toString cfg.output} ${lib.concatStringsSep " " args} \
            --prune-bind-mounts ${if cfg.pruneBindMounts then "yes" else "no"} \
            ${lib.concatStringsSep " " cfg.extraFlags}
        '';
      serviceConfig = {
        CapabilityBoundingSet = "CAP_DAC_READ_SEARCH CAP_CHOWN";
        Nice = 19;
        IOSchedulingClass = "idle";
        IPAddressDeny = "any";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateTmp = "yes";
        PrivateDevices = true;
        PrivateNetwork = "yes";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        RestrictAddressFamilies = "AF_UNIX";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        ReadOnlyPaths = "/";
        # Use dirOf cfg.output because mlocate creates temporary files next to
        # the actual database. We could specify and create them as well,
        # but that would make this quite brittle when they change something.
        # NOTE: If /var/cache does not exist, this leads to the misleading error message:
        # update-locatedb.service: Failed at step NAMESPACE spawning …/update-locatedb-start: No such file or directory
        ReadWritePaths = dirOf cfg.output;
        SystemCallArchitectures = "native";
        SystemCallFilter = "@system-service @chown";
      };
    };

    systemd.timers.update-locatedb = lib.mkIf (cfg.interval != "never") {
      description = "Update timer for locate database";
      partOf = [ "update-locatedb.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ SuperSandro2000 ];
}
