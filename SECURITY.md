# Security Policy

## Reporting

Do not open a public issue containing credentials, tenant data, private IP plans, or exploitable environment details. Revoke exposed credentials first, preserve appropriate audit evidence, and use the repository owner's private security contact.

## Repository rules

- Never commit SSH private keys, passwords, tokens, connection strings, or real customer data.
- Treat parameter files and screenshots as potentially sensitive.
- Restrict SSH to an approved CIDR; `0.0.0.0/0` is not acceptable.
- Review What-If output before every deployment.
- This learning architecture is not approved as a production baseline.
