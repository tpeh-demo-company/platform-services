# The Platform Engineer's Handbook - Platform Services

This repo is the GitOps source that Flux reconciles onto the cluster: platform-wide services (e.g. cert-manager, Istio, OPA/Gatekeeper, monitoring) defined as [Flux Operator](https://fluxcd-operator.dev/) `ResourceSet`s, laid out as a Kustomize base plus one overlay per environment. 


## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [flux2 cli](https://fluxcd.io/flux/installation/)
- [conftest](https://www.conftest.dev/)
- [flate](https://github.com/home-operations/flate)
- [sops](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age)
- [mise](https://mise.jdx.dev/)

## Layout

```text
environments/
├── base/
│   ├── cert-manager/
│   │   ├── namespace.yaml
│   │   ├── app/
│   │   └── ca/
│   ├── istio/
│   │   ├── app/
│   │   └── ...
│   └── ...
├── staging/
│   ├── cert-manager/
│   ├── istio/
│   ├── ...
│   └── kustomization.yaml
└── production/
    ├── istio/
    ├── ...
    └── kustomization.yaml
```

Each environment is a standard Kustomize overlay on top of the relevant `base/` components, with a `labels:` block (`env: <name>`) applied to everything it builds.

## Conventions

- **One `ResourceSet` per concern, one folder per `ResourceSet`.** A base component with multiple independently-reconciled pieces (e.g istio , gateway , mtls ) gets one subfolder per piece.

- **Ordering is expressed via `spec.dependsOn`, not folder nesting.** E.g. `istio-gateway` and `istio-mtls` both `dependsOn: istio`.

- **Per-environment overrides use a `ResourceSetInputProvider`.** Each env gets one `<component>/inputprovider.yaml`, labelled `app: <component>`, holding that component's values. Every `ResourceSet` of the component selects that label, so a component with several `ResourceSet`s (istio, monitoring) shares one provider and uses namespaced keys (`kialiVersion`, `tempoVersion`, ...). Versions come from `<< inputs.version >>` or `<< inputs.<name>Version >>`; `policy/` enforces this.

- **Multitenancy is locked down; every object names its ServiceAccount.** The `platform-services` `Kustomization` reconciles as `flux-infra` (cluster-admin). Each `ResourceSet` sets `spec.serviceAccountName: flux-infra`, and every `HelmRelease`/`Kustomization` it generates sets `serviceAccountName: flux` (or `flux-infra` for objects living in `flux-system`).

- **Namespaces and the `flux` ServiceAccount are plain files at component level**, not inside a `ResourceSet`: `environments/base/<component>/namespace.yaml` holds the `Namespace`, the `flux` ServiceAccount and a `ClusterRoleBinding` to `cluster-admin`, listed first in the component's `kustomization.yaml`. Namespaces shared by several `ResourceSet`s (`istio-system`, `monitoring`) are declared once this way.

- **A `HelmRelease`'s source lives in the same namespace as the release.** `--no-cross-namespace-refs` is on, so the `HelmRepository`/`OCIRepository` and any `chartRef`/`sourceRef` are created in the release's namespace, and `createNamespace` is not used.

## Environments

- **`staging`** — reconciled from the `main` branch (the `platform-sandbox` cluster).
- **`production`** — the production-equivalent overlay, carrying the same components as `staging`, reconciled from the `production` branch (the `app-dev` cluster). Promote by merging `main` into `production`.

## Validating changes locally

```bash
# Lint every manifest under environments/ against the Rego policies in policy/
conftest test environments/ -p policy/

# Confirm every Kustomization/ResourceSet in environments/ actually builds
flate test all --path ./environments
```

Both run in CI on every PR (`.github/workflows/validate.yml`).

## Secrets

Secret values are encrypted with [SOPS](https://github.com/getsops/sops) using age (`.sops.yaml`). A component's secret manifest goes in `environments/<env>/<component>/secret.yaml`, alongside its `inputprovider.yaml`/`patch.yaml`; `.sops.yaml` matches any file named `secret.yaml` and encrypts only its `data`/`stringData` values, so the rest of the manifest stays readable in diffs.

Flux's `Kustomization` for each environment (in `platform-gitops`) has `spec.decryption` pointed at a `flux-system/sops-age` Secret, created by `platform-core`'s Pulumi stack (`pulumi/modules/flux.py`) from an age private key stored in Bitwarden.

## Adding a new component

1. Under `environments/base/<component>/`, create one subfolder per independently-reconciled concern (or leave it flat if there's only one), each with a `ResourceSet`.
2. If a concern must reconcile after another, set `spec.dependsOn` on its `ResourceSet` to point at the one it depends on.
3. Wire `environments/base/<component>` into every environment overlay that should run it.
4. If the component needs per-environment values, add a `ResourceSetInputProvider` under `environments/<env>/<component>/`.
5. Add `environments/base/<component>/namespace.yaml` (`Namespace`, `flux` ServiceAccount, `ClusterRoleBinding`), set `serviceAccountName` on the `ResourceSet` and on every `HelmRelease`/`Kustomization` it generates, and put the release's source in the release's namespace.
