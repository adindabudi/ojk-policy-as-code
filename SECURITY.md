# Security policy

## Supported versions

Security fixes go to the `main` branch only, so use the latest commit on `main`. [CHANGELOG.md](CHANGELOG.md) lists the versions. The version of an initiative deployed in Azure is in its `metadata.version`.

## Report a vulnerability

Don't report security vulnerabilities through public GitHub issues, discussions or pull requests.

Report them privately through GitHub instead:

1. Open the [**Security** tab](https://github.com/adindabudi/ojk-policy-as-code/security) of this repository.
2. Select **Report a vulnerability**.
3. Fill in the form and submit it. Only you and the maintainer can see the report.

GitHub describes these steps in [Privately reporting a security vulnerability](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately). If you don't see **Report a vulnerability**, open an issue that asks the maintainer to contact you, without any details of the vulnerability.

Include as much of the following as you can:

- The files that are affected, for example a template, a custom policy, a script or the workflow.
- The type of issue, for example:
  - A script that exposes a credential.
  - A role assignment with more access than it needs.
  - A custom policy that a resource can get around.
  - A workflow that runs untrusted code with access to Azure.
- Steps to reproduce the issue, and what an attacker could do with it.
- Proof-of-concept code, if you have it.

Don't include real tenant, subscription or resource IDs, resource names, credentials or OJK approval letter numbers.

## What happens next

This is a personal project, maintained on a best-effort basis with no service level. The maintainer confirms that the report arrived, works on a fix in a private security advisory, and publishes the advisory together with the fix. Reporters are credited in the advisory unless they ask not to be.

## Where to report other issues

- Vulnerabilities in Azure services or other Microsoft products, including Azure Policy built-in definitions and the Azure Connected Machine agent: report them to the [Microsoft Security Response Center (MSRC)](https://msrc.microsoft.com/report/vulnerability/new).
- Vulnerabilities in Terraform, the AzureRM provider, Bicep or GitHub Actions: report them to the project that maintains them.
- A checklist row that isn't mapped, or a control that audits instead of denies: these are design choices, so open an issue to discuss them.
