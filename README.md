# unrooted's blog

Source for [unrooted.github.io](https://unrooted.github.io).

Hugo + the `terminal` theme, built with Nix. Deployed via GitHub Actions on every push to `master`.

## Develop

```sh
nix develop          # drop into a shell with hugo, dart-sass, go pinned
nix run .#serve      # local preview at http://localhost:1313 (drafts included)
nix build            # production build to ./result
```

## Update the theme

```sh
nix run .#update-theme   # refreshes _vendor/ from upstream
```

Commit the refreshed `_vendor/` afterwards.
