// The jsonnet file used to generate the Kubernetes manifests.
local tempo = import 'microservices/tempo.libsonnet';
local k = import 'ksonnet-util/kausal.libsonnet';
local container = k.core.v1.container;
local containerPort = k.core.v1.containerPort;

tempo {
    _images+:: {
        tempo: 'grafana/tempo:latest',
        tempo_query: 'grafana/tempo-query:latest',
    },

    tempo_distributor_container+:: container.withPorts([
            containerPort.new('jaeger-grpc', 14250),
            containerPort.new('jaeger-http', 14268),
            containerPort.new('jaeger-binary', 6832),
            containerPort.new('jaeger-compact', 6831),
            containerPort.new('otlp-grpc', 4317),
            containerPort.new('otlp-http', 4318),
        ]),

    _config+:: {
        namespace: 'tempo',

        compactor+: {
            replicas: 1,
        },
        query_frontend+: {
            replicas: 2,
        },
        querier+: {
            replicas: 2,
        },
        ingester+: {
            replicas: 2,
            pvc_size: '10Gi',
            pvc_storage_class: 'nfs-client',
        },
        distributor+: {
            replicas: 2,
            receivers: {
                jaeger: {
                    protocols: {
                        grpc: {
                            endpoint: '0.0.0.0:14250',
                        },
                        thrift_binary: {
                            endpoint: '0.0.0.0:6832',
                        },	
                        thrift_compact: {
                            endpoint: '0.0.0.0:6831',
                        },
                        thrift_http: {
                            endpoint: '0.0.0.0:14268',
                        },
                     },
                },
                otlp: {
                    protocols: {
                        grpc: {
                            endpoint: '0.0.0.0:4317',
                        },
                        http: {
                            endpoint: '0.0.0.0:4318',
                        },
                    },
                },
            },
        },

        metrics_generator+: {
            replicas: 1,
            ephemeral_storage_request_size: '10Gi',
            ephemeral_storage_limit_size: '11Gi',
            pvc_size: '10Gi',
            pvc_storage_class: 'nfs-client',
        },

        memcached+: {
            replicas: 2,
        },

        bucket: 'tempo-data',
        backend: 's3',
    },

    tempo_config+:: {
        storage+: {
            trace+: {
                s3: {
                    bucket: $._config.bucket,
                    access_key: 'minio',
                    secret_key: 'minio123',
                    endpoint: 'minio:9000',
                    insecure: true,
                },
            },
        },
        metrics_generator+: {
            processor: {
                span_metrics: {},
                service_graphs: {},
            },
            registry+: {
                external_labels: {
                    source: 'tempo',
                },
            },
            storage+: {
                remote_write: [
                    {
                        url: 'http://prometheus-service.monitoring:80/api/v1/write',
                        send_exemplars: true,
                        //basic_auth: {
                        //    username: '<username>',
                        //    password: '<password>',
                        //},
                    }
                ],
            },
        },
        overrides+: {
            metrics_generator_processors: ['service-graphs', 'span-metrics'],
        },
    },

    tempo_ingester_container+:: {
      securityContext+: {
        runAsUser: 0,
      },
    },

    local statefulSet = $.apps.v1.statefulSet,
    tempo_ingester_statefulset+:
        statefulSet.mixin.spec.withPodManagementPolicy('Parallel'),
}
