{
  lib,
  pkgs,
  stdenv,
  callPackages,
  fetchFromGitHub,
  postgresql,
  rust-bin,
  latestOnly ? false,
}:
let
  pname = "vchord";
  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).${pname};
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  versionsToUse =
    if latestOnly then
      { "${latestVersion}" = supportedVersions.${latestVersion}; }
    else
      supportedVersions;
  versionsBuilt = if latestOnly then [ latestVersion ] else versions;
  numberOfVersionsBuilt = builtins.length versionsBuilt;
  build =
    version: value:
    let
      cargo = rust-bin.nightly.latest.default;
      mkPgrxExtension = callPackages ../../cargo-pgrx/mkPgrxExtension.nix {
        rustVersion = value.rust;
        pgrxVersion = value.pgrx;
      };
      src = fetchFromGitHub {
        owner = "tensorchord";
        repo = "VectorChord";
        rev = value.revision or "refs/tags/${version}";
        hash = value.hash;
      };
    in
    mkPgrxExtension rec {
      inherit
        pname
        version
        postgresql
        src
        ;

      nativeBuildInputs = [
        cargo
        pkgs.perl
      ];
      buildInputs = [ postgresql ];
      CARGO = "${cargo}/bin/cargo";
      RUSTC = "${cargo}/bin/rustc";
      usePgTestCheckFeature = false;
      cargoLock = {
        lockFile = "${src}/Cargo.lock";
        allowBuiltinFetchGit = true;
      };
      # VectorChord 1.0.0 uses NonNull::from_ref, which is unstable on our toolchain.
      # Replace it with the stable equivalent. Also relax 2024-edition unsafe-op lint
      # to avoid mass intrinsic call-site failures in upstream SIMD code.
      postPatch = ''
        substituteInPlace Cargo.toml \
          --replace-fail 'rust.unsafe_op_in_unsafe_fn = "deny"' 'rust.unsafe_op_in_unsafe_fn = "allow"'
        substituteInPlace crates/small_iter/src/borrowed.rs \
          --replace-fail "NonNull::from_ref(slice)" "NonNull::from(slice)"
        sed -i '1i#![feature(generic_arg_infer)]' crates/vchordrq/src/lib.rs
        # Disable AVX-512 (v4) variants on stable toolchains.
        # Upstream uses many v4-specific intrinsics and target_feature gates.
        find crates/simd/src -name '*.rs' -print0 | xargs -0 sed -i \
          -e 's/#\[crate::target_cpu(enable = "v4")\]/#[cfg(any())]/g' \
          -e 's/@"v4:avx512vpopcntdq", //g' \
          -e 's/@"v4:avx512fp16", //g' \
          -e 's/@"v4", //g'
        sed -i '/let target = version.target.clone();/a\
        if target.starts_with("v4") {\
            continue;\
        }' crates/simd_macros/src/lib.rs
        sed -i "/for s in attr.enable.split(',') {/a\\
        if s == \\\"v4\\\" {\\
            result.extend(quote::quote!(#[cfg(any())]));\\
            continue;\\
        }" crates/simd_macros/src/lib.rs
      '';
      buildFeatures = [ "pg${lib.versions.major postgresql.version}" ];

      env = lib.optionalAttrs stdenv.isDarwin {
        POSTGRES_LIB = "${postgresql}/lib";
        RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
      };

      postInstall = ''
        mv $out/lib/${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        sed -e "/^default_version =/d" \
            -e "s|^module_pathname = .*|module_pathname = '\$libdir/${pname}'|" \
          $out/share/postgresql/extension/${pname}.control > $out/share/postgresql/extension/${pname}--${version}.control
        rm $out/share/postgresql/extension/${pname}.control

        if [[ "${version}" == "${latestVersion}" ]]; then
          {
            echo "default_version = '${latestVersion}'"
            cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
          } > $out/share/postgresql/extension/${pname}.control
          ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}
        fi
      '';

      meta = with lib; {
        description = "VectorChord vector search extension for PostgreSQL";
        homepage = "https://github.com/tensorchord/VectorChord";
        license = licenses.agpl3Only;
        inherit (postgresql.meta) platforms;
      };
    };
  packages = builtins.attrValues (lib.mapAttrs build versionsToUse);
in
(pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];

  postBuild = ''
    (set -x
       test "$(ls -A $out/lib/${pname}*${postgresql.dlSuffix} | wc -l)" = "${
         toString (numberOfVersionsBuilt + 1)
       }"
    )
  '';

  passthru = {
    versions = versionsBuilt;
    numberOfVersions = numberOfVersionsBuilt;
    inherit pname latestOnly;
    defaultSettings = {
      shared_preload_libraries = [ "vchord" ];
    };
    version =
      if latestOnly then
        latestVersion
      else
        "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}).overrideAttrs
  (_: {
    requiredSystemFeatures = [ "big-parallel" ];
  })
