{ lib
, stdenv
, fetchurl
, squashfsTools
, unzip
, makeWrapper
, python3
, zlib
, bzip2
, sqlite
, glibc
, lock
}:

stdenv.mkDerivation rec {
  pname = "simple-bpt";
  version = lock.version;

  src = fetchurl {
    url = "https://www.gov.uk/government/uploads/uploaded/hmrc/${lock.linux_zip}";
    sha256 = lock.sha256;
  };

  nativeBuildInputs = [ squashfsTools unzip makeWrapper python3 ];
  buildInputs = [ zlib bzip2 sqlite glibc ];

  unpackPhase = ''
    runHook preUnpack
    unzip -q $src
    appimage=$(find . -maxdepth 1 -name '*.AppImage' -print -quit)
    [ -n "$appimage" ] || { echo "no AppImage in $src"; exit 1; }
    offset=$(python3 ${../appimage-offset.py} "$appimage")
    echo "squashfs at byte $offset"
    unsquashfs -q -f -o "$offset" -d squashfs-root "$appimage"
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    [ -d squashfs-root/usr/bptserver ] \
      || { echo "no usr/bptserver"; exit 1; }

    mkdir -p $out/libexec/simple-bpt
    cp -a squashfs-root/usr/bptserver/. $out/libexec/simple-bpt/
    chmod -R u+rwX $out/libexec/simple-bpt
    chmod +x $out/libexec/simple-bpt/rti.linux

    unzip -l $out/libexec/simple-bpt/rti.linux > listing \
      || { echo "rti.linux has no appended zip"; exit 1; }
    grep -q '__main__\.pyc' listing \
      || { echo "rti.linux has no __main__.pyc"; exit 1; }
    [ -e $out/libexec/simple-bpt/sqlite3.db ] \
      || { echo "no seed database"; exit 1; }

    python3 ${../inject-settings.py} $out/libexec/simple-bpt/rti.linux \
         simple_bpt_settings.py ${../simple_bpt_settings.py}
    unzip -l $out/libexec/simple-bpt/rti.linux | grep -q simple_bpt_settings.py
    
    install -Dm755 ${../bin/simple-bpt} $out/bin/simple-bpt
    wrapProgram $out/bin/simple-bpt \
      --set BPT_SERVER_DIR $out/libexec/simple-bpt \
      --set BPT_LOADER ${glibc}/lib/ld-linux-x86-64.so.2 \
      --prefix LD_LIBRARY_PATH : \
        "$out/libexec/simple-bpt:${lib.makeLibraryPath [ zlib bzip2 sqlite glibc ]}"

    echo "${version}" > $out/libexec/simple-bpt/VERSION
    runHook postInstall
  '';

  meta = with lib; {
    description = "HMRC Basic PAYE Tools, headless";
    homepage = "https://github.com/angus-forrest-uk/simple-bpt";
    downloadPage = "https://www.gov.uk/basic-paye-tools";
    license = licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "simple-bpt";
  };
}
