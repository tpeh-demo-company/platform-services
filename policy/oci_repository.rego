package main

import future.keywords.if
import future.keywords.contains

# OCIRepository resources inside a ResourceSet must use the
# << inputs.version >> (or a component-specific << inputs.<name>Version >>)
# placeholder in spec.ref.tag.

deny contains msg if {
  input.kind == "ResourceSet"
  some resource in input.spec.resources
  resource.kind == "OCIRepository"
  tag := resource.spec.ref.tag
  not regex.match(`<< inputs\.([A-Za-z]*[vV])ersion >>`, tag)
  msg := sprintf(
    "ResourceSet %s: OCIRepository %s ref.tag '%s' must use an inputs version placeholder",
    [input.metadata.name, resource.metadata.name, tag],
  )
}
