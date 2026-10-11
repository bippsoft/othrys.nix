# Security Policy

## Supported Versions

othrys.nix is pre-1.0 and ships from one line of development. Security fixes
land on `main` and in the next tagged release. Older tags are not patched.

| Version | Supported |
|---------|-----------|
| Latest tagged minor release | Yes |
| `main` | Yes |
| Any earlier tag | No |

## Reporting a Vulnerability

Report vulnerabilities through GitHub private vulnerability reporting. Open the
[Security tab](https://github.com/bippsoft/othrys.nix/security/advisories/new)
of this repository and choose "Report a vulnerability". Do not open a public
issue, a discussion or a pull request for a suspected vulnerability.

A useful report names the module and option involved, the revision or tag, a
minimal configuration that shows the problem, and what an attacker gains.

## What to Expect

- An acknowledgement within 7 days.
- An assessment, with a fix plan or an explanation of why the report is not
  treated as a vulnerability, within 30 days.
- Coordinated disclosure. The advisory is published when a fix is released, or
  90 days after the report, whichever comes first. A longer window is agreed
  with the reporter when a fix needs it.
- Credit in the advisory, unless the reporter asks otherwise.

## Advisories

Advisories are published as GitHub security advisories on this repository,
under its Security tab.

Dependabot watches the pinned GitHub Actions and nothing else. No job scans the
Nix inputs, or the packages a module installs from them, for known
vulnerabilities. The `flake-inputs` workflow reports whether the nixpkgs pin is
recent and still supported, which is a different question. A consumer follows
the advisories of nixpkgs and of the other inputs through those projects.

## Scope

In scope:

- The NixOS modules under `modules/` and the options they expose.
- The scripts under `scripts/` and the packages the flake exports.
- The workflows under `.github/workflows/`.

Out of scope:

- Vulnerabilities in upstream software that a module merely enables. Report
  those to nixpkgs or to the upstream project.
- The configuration, secrets and infrastructure of a flake that consumes this
  one.
- Behaviour the documentation already states as a limitation.

## Verifying Releases

Release tags from `v0.4.0` onward are signed annotated tags, and
`git tag -v <tag>` verifies them. Tags from `v0.1.0` through `v0.3.1` were
published unsigned and stay as they are.

The maintainer key is in the repository as `keys/maintainer.asc`. Its
fingerprint is

```text
6484 E76F 0D85 D217 463A  D145 CEC8 EDDD 3028 A8FE
```

Compare that fingerprint with a copy from a second source before trusting
it, since a repository that was tampered with can carry a replaced key
beside a replaced tag. Then import the key and verify a tag.

```bash
gpg --show-keys --with-fingerprint keys/maintainer.asc
gpg --import keys/maintainer.asc
git tag -v v0.14.0
```

Every commit pushed to `main` is verified against the keys in `keys/` by the
`signatures` job of the build workflow. The same key is the trust root to
give `othrys.system.autoUpgrade.verify.publicKeys` on a host that follows
this repository's releases.

## Safe Harbor

Research carried out in good faith under this policy is welcome. The maintainers
will not pursue or support legal action against anyone who stays within the
scope above, avoids harm to other people's systems and data, and allows
reasonable time for a response before disclosing. Testing belongs on your own hosts. Nothing here
authorises access to infrastructure run by this project's maintainers or by
anyone else.
