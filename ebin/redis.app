{application, redis, [
    {description, "Erlang redis client"},
    {vsn, "1.0"},
    {modules, [redis, redis_app, redis_pool, redis_uri]},
    {applications, [stdlib, kernel, sasl]},
    {registered, []},
    {mod, {redis_app, []}}
]}.
