package main

import future.keywords.if
import future.keywords.contains

# ResourceSet must carry all four reconcile annotations.
# reconcile and force enforce fixed values; reconcileEvery and reconcileTimeout
# are presence-only (values vary per ResourceSet).

deny contains msg if {
  input.kind == "ResourceSet"
  some key, expected in {"fluxcd.controlplane.io/reconcile": "enabled", "fluxcd.controlplane.io/force": "true"}
  not input.metadata.annotations[key] == expected
  msg := sprintf(
    "ResourceSet %s annotation %s must be '%s'",
    [input.metadata.name, key, expected],
  )
}

deny contains msg if {
  input.kind == "ResourceSet"
  some key in ["fluxcd.controlplane.io/reconcileEvery", "fluxcd.controlplane.io/reconcileTimeout"]
  not input.metadata.annotations[key]
  msg := sprintf(
    "ResourceSet %s is missing required annotation %s",
    [input.metadata.name, key],
  )
}

# Every HelmRelease inside a ResourceSet's resources block must use the
# << inputs.version >> (or << inputs.<name>Version >>) placeholder so versions are
# driven by the InputProvider.

deny contains msg if {
  input.kind == "ResourceSet"
  some resource in input.spec.resources
  resource.kind == "HelmRelease"
  not resource.spec.chartRef
  not resource.spec.chart.spec.version
  msg := sprintf(
    "ResourceSet %s: HelmRelease %s is missing spec.chart.spec.version",
    [input.metadata.name, resource.metadata.name],
  )
}

deny contains msg if {
  input.kind == "ResourceSet"
  some resource in input.spec.resources
  resource.kind == "HelmRelease"
  not resource.spec.chartRef
  version := resource.spec.chart.spec.version
  not regex.match(`<< inputs\.([A-Za-z]*[vV])ersion >>`, version)
  msg := sprintf(
    "ResourceSet %s: HelmRelease %s chart version '%s' must use an inputs version placeholder",
    [input.metadata.name, resource.metadata.name, version],
  )
}
