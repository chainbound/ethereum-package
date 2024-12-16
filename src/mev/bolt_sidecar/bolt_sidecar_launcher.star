redis_module = import_module("github.com/kurtosis-tech/redis-package/main.star")
postgres_module = import_module("github.com/kurtosis-tech/postgres-package/main.star")
constants = import_module("../../package_io/constants.star")
input_parser = import_module("../../package_io/input_parser.star")
validator_keystore_generator = import_module("../../prelaunch_data_generator/validator_keystores/validator_keystore_generator.star")

BOLT_SIDECAR_COMMITMENTS_API_PORT = 9061
BOLT_SIDECAR_METRICS_PORT = 9063
BOLT_SIDECAR_KEYS_DIRMOUNT_PATH_ON_SERVICE = "/keys"

# The min/max CPU/memory that bolt-sidecar can use
BOLT_SIDECAR_MIN_CPU = 100
BOLT_SIDECAR_MAX_CPU = 1000
BOLT_SIDECAR_MIN_MEMORY = 128
BOLT_SIDECAR_MAX_MEMORY = 1024

def launch_bolt_sidecar(
    plan,
    image,
    sidecar_config,
    network_params,
    node_selectors,
):
    env_vars = {
        "RUST_LOG": "bolt_sidecar=trace",
    }

    node_keystore_path = validator_keystore_generator.NODE_KEYSTORES_OUTPUT_DIRPATH_FORMAT_STR.format(sidecar_config["participant_index"])
    full_keystore_path = "{0}{1}/keys".format(BOLT_SIDECAR_KEYS_DIRMOUNT_PATH_ON_SERVICE, node_keystore_path)
    full_keystore_secrets_path = "{0}{1}/secrets".format(BOLT_SIDECAR_KEYS_DIRMOUNT_PATH_ON_SERVICE, node_keystore_path)

    cmd = [
        "--execution-api-url",
        sidecar_config["execution_api_url"],
        "--beacon-api-url",
        sidecar_config["beacon_api_url"],
        "--engine-api-url",
        sidecar_config["engine_api_url"],
        "--constraints-api-url",
        sidecar_config["constraints_api_url"],
        "--constraints-proxy-port",
        str(input_parser.BOLT_SIDECAR_CONSTRAINTS_PROXY_PORT),
        "--engine-jwt-hex",
        sidecar_config["jwt_hex"],
        "--fee-recipient",
        "0x0000000000000000000000000000000000000000",
        "--builder-private-key", # Random private key for testing
        "0x20c815cb2d37561479c7b6cae9737356b144760d00f1387bff17df4a3712c262",
        # random private key for testing
        "--operator-private-key",
        "0x18d1c5302e734fd6fbfaa51828d42c4c6d3cbe020c42bab7dd15a2799cf00b82",
        "--commitment-deadline",
        str(100),
        "--chain",
        network_params.network,
        "--slot-time",
        str(network_params.seconds_per_slot),
        # "--keystore-password",
        # validator_keystore_generator.PRYSM_PASSWORD,
        "--keystore-secrets-path",
        full_keystore_secrets_path,
        "--keystore-path",
        full_keystore_path,
        "--metrics-port",
        str(BOLT_SIDECAR_METRICS_PORT),
    ]

    if len(sidecar_config["firewall_rpcs"]) > 0:
        cmd.append("--firewall-rpcs")
        cmd.append(",".join(sidecar_config["firewall_rpcs"]))
    else:
        cmd.append("--port")
        cmd.append(str(BOLT_SIDECAR_COMMITMENTS_API_PORT))


    api = plan.add_service(
        name=sidecar_config["service_name"],
        config=ServiceConfig(
            image=image,
            cmd=cmd,
            # + mev_params.mev_relay_api_extra_args,
            ports={
                "api": PortSpec(
                    number=BOLT_SIDECAR_COMMITMENTS_API_PORT, transport_protocol="TCP"
                ),
                "bolt-sidecar": PortSpec(
                    number=input_parser.BOLT_SIDECAR_CONSTRAINTS_PROXY_PORT, transport_protocol="TCP"
                ),
                "metrics": PortSpec(
                    number=BOLT_SIDECAR_METRICS_PORT, transport_protocol="TCP"
                ),
            },
            files={
                BOLT_SIDECAR_KEYS_DIRMOUNT_PATH_ON_SERVICE: sidecar_config["validator_keystore_files_artifact_uuid"],
            },
            env_vars=env_vars,
            min_cpu=BOLT_SIDECAR_MIN_CPU,
            max_cpu=BOLT_SIDECAR_MAX_CPU,
            min_memory=BOLT_SIDECAR_MIN_MEMORY,
            max_memory=BOLT_SIDECAR_MAX_MEMORY,
            node_selectors=node_selectors,
        ),
    )

    return struct(
        ip_addr=api.ip_address,
        metrics_port_num=BOLT_SIDECAR_METRICS_PORT,
    )
