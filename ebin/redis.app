{application, redis, [
    {description, "hot shit!"},
    {vsn, "1.0"},
    {modules, [redis, redis_app, redis_pool, redis_uri]},
    {applications, [stdlib, kernel, sasl]},
    {registered, [redis]},
	{mod, {redis_app, []}}
]}.
