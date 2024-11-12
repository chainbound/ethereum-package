redis_module = import_module("github.com/kurtosis-tech/redis-package/main.star")
postgres_module = import_module("github.com/kurtosis-tech/postgres-package/main.star")
constants = import_module("../../package_io/constants.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")
static_files = import_module("../../static_files/static_files.star")

# Misc constants
SERVICE_NAME="helix-relay"
HELIX_CONFIG_FILENAME="helix-config.yaml"
HELIX_NETWORK_CONFIG_FILENAME = "network-config.yaml"
HELIX_CONFIG_MOUNT_DIRPATH_ON_SERVICE="/config"

# The secret key and public key for the relay, exposed as environment variables
DUMMY_SECRET_KEY = "0x607a11b45a7219cc61a3d9c5fd08c7eebd602a6a19a977f8d3771d5711a550f2"
DUMMY_PUB_KEY = "0xa55c1285d84ba83a5ad26420cd5ad3091e49c55a813eee651cd467db38a8c8e63192f47955e9376f6b42f6d190571cb5"

# This is currenlty hardcoded in the Helix relay
HELIX_RELAY_ENDPOINT_PORT = 4040
HELIX_RELAY_WEBSITE_PORT = 8080

# The min/max CPU/memory that mev-relay can use
RELAY_MIN_CPU = 2000 # 2 cores
RELAY_MAX_CPU = 4000 # 2 cores
RELAY_MIN_MEMORY = 128
RELAY_MAX_MEMORY = 1024

# The min/max CPU/memory that postgres can use
POSTGRES_MIN_CPU = 10
POSTGRES_MAX_CPU = 1000
POSTGRES_MIN_MEMORY = 32
POSTGRES_MAX_MEMORY = 1024

# The min/max CPU/memory that redis can use
REDIS_MIN_CPU = 10
REDIS_MAX_CPU = 1000
REDIS_MIN_MEMORY = 16
REDIS_MAX_MEMORY = 1024

def launch_helix_relay(
    plan,
    mev_params,
    network_params,
    beacon_uris,
    validator_root,
    builder_uri,
    seconds_per_slot,
    persistent,
    genesis_timestamp,
    global_node_selectors,
):
    plan.print(network_params)

    node_selectors = global_node_selectors

    # Read the template files with Helix configuration and network configuration
    helix_config_template = read_file(
        static_files.HELIX_CONFIG_TEMPLATE_FILEPATH
    )
    helix_network_config_template = read_file(
        static_files.HELIX_NETWORK_CONFIG_TEMPLATE_FILEPATH
    )

    # Start both the Redis and Postgres services
    redis = redis_module.run(
        plan,
        service_name="mev-relay-redis",
        min_cpu=REDIS_MIN_CPU,
        max_cpu=REDIS_MAX_CPU,
        min_memory=REDIS_MIN_MEMORY,
        max_memory=REDIS_MAX_MEMORY,
        node_selectors=node_selectors,
    )
    postgres = postgres_module.run(
        plan,
        # Postgres image with TimescaleDB extension:
        # References:
        # - https://docs.timescale.com/
        # - https://github.com/gattaca-com/helix/blob/9e078f1ec4710869b2e41e1ca20d31e1c7cfde52/crates/database/src/postgres/postgres_db_service_tests.rs#L41-L44
        image="timescale/timescaledb-ha:pg16",
        password="postgres",
        user="postgres",
        database="helixdb",
        service_name="helix-postgres",
        persistent=persistent,
        launch_adminer=True,
        min_cpu=POSTGRES_MIN_CPU,
        max_cpu=POSTGRES_MAX_CPU,
        min_memory=POSTGRES_MIN_MEMORY,
        max_memory=POSTGRES_MAX_MEMORY,
        node_selectors=node_selectors,
    )

    image = mev_params.helix_relay_image

    # Convert beacon_uris from a comma-separated string to a list of URIs
    beacon_uris = [uri.strip() for uri in beacon_uris.split(",")]

    network_config_dir_path_on_service = "{0}/{1}".format(
        HELIX_CONFIG_MOUNT_DIRPATH_ON_SERVICE, HELIX_NETWORK_CONFIG_FILENAME
    )

    # See https://github.com/kurtosis-tech/postgres-package#use-this-package-in-your-package
    # and https://docs.kurtosis.com/api-reference/starlark-reference/service/
    helix_config_template_data = new_config_template_data(
        postgres.service.hostname,
        postgres.port.number,
        postgres.database,
        postgres.user,
        postgres.password,
        redis.url,
        builder_uri,
        beacon_uris,
        network_config_dir_path_on_service,
        validator_root,
        genesis_timestamp,
        mev_params.helix_relay_config_extension,
    )

    helix_config_template_and_data = shared_utils.new_template_and_data(
        helix_config_template, helix_config_template_data
    )

    helix_network_config_template_and_data = shared_utils.new_template_and_data(
        helix_network_config_template, network_params
    )
    template_and_data_by_rel_dest_filepath = {}
    template_and_data_by_rel_dest_filepath[HELIX_CONFIG_FILENAME] = helix_config_template_and_data
    template_and_data_by_rel_dest_filepath[HELIX_NETWORK_CONFIG_FILENAME] = helix_network_config_template_and_data

    config_files_artifact_name = plan.render_templates(
        template_and_data_by_rel_dest_filepath
    )

    env_vars = {
        "RELAY_KEY": DUMMY_SECRET_KEY,
        "RUST_LOG": "helix_cmd=trace,helix_api=trace,helix_common=trace,helix_datastore=trace,helix_housekeeper=trace,helix_database=trace,helix_beacon_client=trace",
    }

    helix = plan.add_service(
        name=SERVICE_NAME,
        config=ServiceConfig(
            image=image,
            files={
                HELIX_CONFIG_MOUNT_DIRPATH_ON_SERVICE: config_files_artifact_name
            },
            cmd=[
                "--config",
                shared_utils.path_join(
                    HELIX_CONFIG_MOUNT_DIRPATH_ON_SERVICE,
                    HELIX_CONFIG_FILENAME,
                )
            ],
            ports={
                "api": PortSpec(
                    number=HELIX_RELAY_ENDPOINT_PORT, transport_protocol="TCP"
                )
                # "website": PortSpec(
                #     number=HELIX_RELAY_WEBSITE_PORT, transport_protocol="TCP"
                # )
            },
            env_vars=env_vars,
            min_cpu=RELAY_MIN_CPU,
            max_cpu=RELAY_MAX_CPU,
            min_memory=RELAY_MIN_MEMORY,
            max_memory=RELAY_MAX_MEMORY,
            node_selectors=node_selectors,
        ),
    )

    plan.print(json.indent(json.encode(helix_config_template_data)))

    return "http://{0}@{1}:{2}".format(
        DUMMY_PUB_KEY, helix.ip_address, HELIX_RELAY_ENDPOINT_PORT
    )

def new_config_template_data(
    postgres_hostname,
    postgres_port,
    postgres_db_name,
    postgres_user,
    postgres_password,
    redis_url,
    blocksim_url,
    beacon_uris,
    network_config_dir_path,
    genesis_validator_root,
    genesis_time,
    config_extension,
):
    config_hashmap = {
        "postgres": {
            "hostname": postgres_hostname,
            "port": postgres_port,
            "db_name": postgres_db_name,
            "user": postgres_user,
            "password": postgres_password,
        },
        "redis": {
            "url": redis_url,
        },
        "simulator": {
            "url": blocksim_url,
        },
        "beacon_clients": [
            {"url": uri} for uri in beacon_uris
        ],
        "network_config": {
            "dir_path": network_config_dir_path,
            "genesis_validator_root": genesis_validator_root,
            "genesis_time": genesis_time,
        },
    }

    if config_extension != None:
        for key, value in config_extension.items():
            config_hashmap[key] = value

    return config_hashmap
