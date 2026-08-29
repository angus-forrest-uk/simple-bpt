# simple-bpt

TODO

## Build

```sh
./build.sh
./build.sh --check
./build.sh --update
```

## Run

```sh
./dist/simple-bpt
```

```
BPT_BIND        127.0.0.1
BPT_PORT        46729
BPT_STATE_DIR   $HOME
BPT_SERVER_DIR  ./bptserver
BPT_CONFIG      /etc/simple-bpt/config
BPT_LOADER      unset
```

## systemd

```sh
./build.sh
sudo ./install.sh
sudo ./install.sh --uninstall
```

```sh
sudo cp systemd/simple-bpt-update.{service,timer} /etc/systemd/system/
sudo systemctl enable --now simple-bpt-update.timer
```

## Nix

```nix
inputs.simple-bpt.url = "github:angus-forrest-uk/simple-bpt";

imports = [ simple-bpt.nixosModules.default ];
nixpkgs.overlays = [ simple-bpt.overlays.default ];
nixpkgs.config.allowUnfree = true;

services.simple-bpt = {
  enable = true;
  bind = "127.0.0.1";
  port = 46729;
};
```

```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#simple-bpt
```
