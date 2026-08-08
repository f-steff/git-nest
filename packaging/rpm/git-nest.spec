# RPM spec for git-nest (STUB -- not yet wired into the release workflow;
# see temp-doc/external-setup-guide.md for the external setup).
#
# When enabled, the release workflow builds an .rpm from the assembled
# tarball (in a fedora container) and publishes it to COPR or a
# self-hosted RPM repo.

Name:           git-nest
Version:        __VERSION__
Release:        1%{?dist}
Summary:        Manage many independent Git repositories as one cohesive project
License:        MIT
URL:            https://github.com/f-steff/git-nest
Source0:        https://github.com/f-steff/git-nest/releases/download/%{version}/git-nest-%{version}.tar.gz
BuildArch:      noarch
Requires:       git

%description
git-nest records and restores reproducible workspaces made from
independent Git repositories, without submodules or monorepo pain.

%prep
%setup -q -c -n git-nest

%install
install -d %{buildroot}%{_bindir}
install -m 0755 git-nest %{buildroot}%{_bindir}/git-nest
install -m 0755 git_nest.sh %{buildroot}%{_bindir}/git_nest.sh
cp -r lib %{buildroot}%{_bindir}/

%files
%{_bindir}/git-nest
%{_bindir}/git_nest.sh
%{_bindir}/lib

%changelog
