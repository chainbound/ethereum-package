redis_module = import_module("github.com/kurtosis-tech/redis-package/main.star")
postgres_module = import_module("github.com/kurtosis-tech/postgres-package/main.star")
constants = import_module("../../package_io/constants.star")
mev_boost_context_util = import_module("../mev_boost/mev_boost_context.star")

MEV_SIDECAR_ENDPOINT = "mev-sidecar-api"

MEV_SIDECAR_ENDPOINT_PORT = 9061

# The min/max CPU/memory that mev-sidecar can use
MEV_SIDECAR_MIN_CPU = 100
MEV_SIDECAR_MAX_CPU = 1000
MEV_SIDECAR_MIN_MEMORY = 128
MEV_SIDECAR_MAX_MEMORY = 1024

def launch_mev_sidecar(
    plan,
    mev_params,
    node_selectors,
    mev_boost_context,
    beacon_client_url
):
    image = mev_params.mev_sidecar_image

    env_vars = {
        "RUST_LOG": "info",
    }

    api = plan.add_service(
        name=MEV_SIDECAR_ENDPOINT,
        config=ServiceConfig(
            image=image,
            cmd=[
                "/bolt-sidecar",
                "--port",
                str(MEV_SIDECAR_ENDPOINT_PORT),
                "--private-key",
                # Random private key for testing, generated with `openssl rand -hex 32`
                "18d1c5302e734fd6fbfaa51828d42c4c6d3cbe020c42bab7dd15a2799cf00b82",
                "--mevboost-url",
                mev_boost_context_util.mev_boost_endpoint(mev_boost_context),
                "--beacon-client-url",
                beacon_client_url
            ],
            # + mev_params.mev_relay_api_extra_args,
            ports={
                "api": PortSpec(
                    number=MEV_SIDECAR_ENDPOINT_PORT, transport_protocol="TCP"
                )
            },
            env_vars=env_vars,
            min_cpu=MEV_SIDECAR_MIN_CPU,
            max_cpu=MEV_SIDECAR_MAX_CPU,
            min_memory=MEV_SIDECAR_MIN_MEMORY,
            max_memory=MEV_SIDECAR_MAX_MEMORY,
            node_selectors=node_selectors,
        ),
    )

    return "http://{0}:{1}".format(
        api.ip_address, MEV_SIDECAR_ENDPOINT_PORT
    )
