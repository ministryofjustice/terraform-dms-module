#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$REPO_ROOT/test"

mkdir -p "$TEST_DIR"

echo "Repo root: $REPO_ROOT"
echo "Test dir: $TEST_DIR"

############################################
# Only the root module test
############################################

ROOT_TEST_FILE="$TEST_DIR/terraform_root_module_test.go"

if [[ -f "$ROOT_TEST_FILE" ]]; then
  echo "Root module test already exists: $ROOT_TEST_FILE"
else
  cat > "$ROOT_TEST_FILE" <<EOF2
package test

import (
  "testing"
  "os"

  "github.com/gruntwork-io/terratest/modules/terraform"
)

// Auto-generated Terratest for the root Terraform module
func TestRootModule(t *testing.T) {
  if os.Getenv("SKIP_TERRAFORM_TESTS") == "true" {
    t.Skip("Skipping Terraform tests because SKIP_TERRAFORM_TESTS is set")
  }

  terraformOptions := &terraform.Options{
    TerraformDir: "..",
    // Vars: map[string]interface{}{
    //   // TODO: add required variables here
    // },
  }

  defer terraform.Destroy(t, terraformOptions)
  terraform.InitAndApply(t, terraformOptions)
}
EOF2

  echo "Generated root module test: $ROOT_TEST_FILE"
fi

echo "Done generating Terratest files."
