# install-substrate.sh

Interactive installer to set up Substrate on GCP.

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/rakyll/install-substrate.sh/main/install-substrate.sh | bash
```

Or run locally:

```bash
./install-substrate.sh
```

Pass flags with `curl` using `bash -s -- [flags]`:

```bash
curl -fsSL https://raw.githubusercontent.com/rakyll/install-substrate.sh/main/install-substrate.sh | bash -s -- --project-id=my-project -y
```

## Flags

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--project-id` | GCP Project ID | Active `gcloud` project |
| `--project-number` | GCP Project Number | Auto-detected |
| `--region` | GCP Region | `us-central1` |
| `--location` | GKE Cluster Zone/Location | `<region>-c` (`us-central1-c`) |
| `--cluster-name` | GKE Cluster Name | `substrate-poc` |
| `--cluster-version` | GKE Cluster Version | GKE default |
| `--machine-type` | gVisor node machine type | `c3-standard-4` |
| `--network` | VPC Network Name | `default` |
| `--subnetwork` | VPC Subnetwork Name | `default` |
| `--snapshots-bucket` | GCS Snapshot Bucket | `substrate-snapshots-$PROJECT_ID` |
| `--gcr-repo` | Container registry for images | `gcr.io/$PROJECT_ID/ate-images` |
| `--store-backend` | State store: `redis` or `postgres` | `redis` |
| `--router` | Router: `envoy` or `agentgateway` | `envoy` |
| `--demo` | Deploy Counter demo: `counter` or `none` | `counter` |
| `--substrate-dir` | Path to local Substrate repository | Cloned if omitted |
| `--substrate-repo` | Git repo URL for Substrate | `https://github.com/agent-substrate/substrate.git` |
| `--substrate-branch` | Git branch to clone | `main` |
| `--skip-bootstrap` | Skip GCP infrastructure provisioning | `false` |
| `-y`, `--yes`, `--non-interactive` | Run without interactive prompts | `false` |
| `--dry-run` | Preview planned configuration and exit | `false` |
| `-h`, `--help` | Show usage information | - |
