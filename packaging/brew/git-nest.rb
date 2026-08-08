# Homebrew formula for git-nest (STUB -- not yet wired into the release
# workflow; see temp-doc/external-setup-guide.md for the external setup).
#
# When enabled, the release workflow builds this formula with the version,
# the release tarball URL, and its sha256, then pushes it to the personal
# tap repo (or submits a PR to homebrew-core).

class GitNest < Formula
  desc "Manage many independent Git repositories as one cohesive project"
  homepage "https://github.com/f-steff/git-nest"
  url "https://github.com/f-steff/git-nest/releases/download/__VERSION__/git-nest-__VERSION__.tar.gz"
  sha256 "__SHA256__"
  license "MIT"

  def install
    bin.install "git-nest"
    bin.install "git_nest.sh"
    lib.install "lib"
    bin.install "install.sh" => "git-nest-install"
    bin.install "uninstall.sh" => "git-nest-uninstall"
  end
end
