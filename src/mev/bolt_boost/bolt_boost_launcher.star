shared_utils = import_module("../../shared_utils/shared_utils.star")
mev_boost_context_module = import_module("../mev_boost/mev_boost_context.star")
static_files = import_module("../../static_files/static_files.star")
constants = import_module("../../package_io/constants.star")
input_parser = import_module("../../package_io/input_parser.star")

BOLT_BOOST_CONFIG_FILENAME="cb-bolt-config.toml"
BOLT_BOOST_CONFIG_MOUNT_DIRPATH_ON_SERVICE="/config"

USED_PORTS = {
    "api": shared_utils.new_port_spec(
        input_parser.FLASHBOTS_MEV_BOOST_PORT, "TCP", wait="5s"
    )
}

# The min/max CPU/memory that mev-boost can use
MIN_CPU = 10
MAX_CPU = 500
MIN_MEMORY = 16
MAX_MEMORY = 256


def launch(
    plan,
    service_name,
    bolt_boost_image,
    relays_config,
    bolt_sidecar_config,
    network_params,
    final_genesis_timestamp,
    global_node_selectors,
):
    plan.print(network_params)
    config = get_bolt_boost_config(
        plan,
        bolt_boost_image,
        relays_config,
        bolt_sidecar_config,
        network_params,
        final_genesis_timestamp,
        global_node_selectors,
    )

    bolt_boost_service = plan.add_service(service_name, config)

    return mev_boost_context_module.new_mev_boost_context(
        bolt_boost_service.ip_address, bolt_boost_service.ports["api"].number
    )


def get_bolt_boost_config(
    plan,
    image,
    relays_config,
    bolt_sidecar_config,
    network_params,
    final_genesis_timestamp,
    node_selectors,
):
    # Read the template file for Bolt Boost configuration
    bolt_boost_config_template = read_file(
        static_files.BOLT_BOOST_CONFIG_TEMPLATE_FILEPATH
    )

    # Generate the data to be used in the Bolt Boost configuration,
    # wrap them together in a struct
    bolt_boost_config_template_data = new_bolt_boost_config_template_data(
        image,
        relays_config,
        bolt_sidecar_config,
        network_params,
        final_genesis_timestamp,
    )
    bolt_boost_config_template_and_data = shared_utils.new_template_and_data(
        bolt_boost_config_template, bolt_boost_config_template_data
    )

    # Map the relative destination filepaths to the template/data pairs
    template_and_data_by_rel_dest_filepath = {}
    template_and_data_by_rel_dest_filepath[BOLT_BOOST_CONFIG_FILENAME] = bolt_boost_config_template_and_data

    # Render the templates to files in the artifact directory
    config_files_artifact_name = plan.render_templates(
        template_and_data_by_rel_dest_filepath
    )

    return ServiceConfig(
        image=image,
        ports=USED_PORTS,
        files={
            BOLT_BOOST_CONFIG_MOUNT_DIRPATH_ON_SERVICE: config_files_artifact_name
        },
        env_vars={
            "RUST_LOG": "debug",
            "CB_CONFIG": shared_utils.path_join(
                BOLT_BOOST_CONFIG_MOUNT_DIRPATH_ON_SERVICE,
                BOLT_BOOST_CONFIG_FILENAME,
            )
        },
        min_cpu=MIN_CPU,
        max_cpu=MAX_CPU,
        min_memory=MIN_MEMORY,
        max_memory=MAX_MEMORY,
        node_selectors=node_selectors,
    )

def new_bolt_boost_config_template_data(
    image,
    relays_config,
    bolt_sidecar_config,
    network_params,
    final_genesis_timestamp,
):
    return {
        "chain_config": {
            "name": network_params.network.capitalize(),
            "genesis_timestamp": final_genesis_timestamp,
            "seconds_per_slot": network_params.seconds_per_slot,
            "genesis_fork_version": constants.GENESIS_FORK_VERSION,
        },
        "image": image,
        "port": input_parser.FLASHBOTS_MEV_BOOST_PORT,
        "relays_config": [
            {
                "id": relay_config["id"],
                "url": relay_config["url"],
            } for relay_config in relays_config
        ],
        "bolt_sidecar_config": {
            "constraints_api_url": bolt_sidecar_config["constraints_api_url"],
            "beacon_api_url": bolt_sidecar_config["beacon_api_url"],
            "execution_api_url": bolt_sidecar_config["execution_api_url"],
            "engine_api_url": bolt_sidecar_config["engine_api_url"],
            "jwt_hex": bolt_sidecar_config["jwt_hex"],
            "metrics_port": bolt_sidecar_config["metrics_port"],
            "builder_proxy_port": input_parser.FLASHBOTS_MEV_BOOST_PORT,
        }
    }
