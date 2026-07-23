#define HL_NAME(n) bevy_##n

#include <hl.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct BridgeWorld BridgeWorld;
typedef struct BridgeQuery BridgeQuery;

extern uint32_t bevy_rs_bridge_version(void);
extern BridgeWorld *bevy_rs_world_new(void);
extern void bevy_rs_world_free(BridgeWorld *world);
extern int32_t bevy_rs_component_register(BridgeWorld *world, uint32_t bridge_id, const char *name, bool sparse);
extern uint32_t bevy_rs_spawn(BridgeWorld *world);
extern bool bevy_rs_entity_exists(BridgeWorld *world, uint32_t entity);
extern uint32_t bevy_rs_entity_generation(BridgeWorld *world, uint32_t entity);
extern bool bevy_rs_despawn(BridgeWorld *world, uint32_t entity);
extern bool bevy_rs_component_insert(BridgeWorld *world, uint32_t entity, uint32_t component, void *root);
extern void *bevy_rs_component_get(BridgeWorld *world, uint32_t entity, uint32_t component);
extern bool bevy_rs_component_has(BridgeWorld *world, uint32_t entity, uint32_t component);
extern bool bevy_rs_component_remove(BridgeWorld *world, uint32_t entity, uint32_t component);
extern BridgeQuery *bevy_rs_query_new(
    BridgeWorld *world,
    const uint32_t *required,
    size_t required_len,
    const uint32_t *excluded,
    size_t excluded_len
);
extern bool bevy_rs_query_refresh(BridgeWorld *world, BridgeQuery *query);
extern uint32_t bevy_rs_query_fill_values(
    BridgeWorld *world,
    const BridgeQuery *query,
    int32_t index,
    void **out,
    size_t out_len
);
extern void bevy_rs_query_free(BridgeQuery *query);
extern int32_t bevy_rs_query_len(const BridgeQuery *query);
extern uint32_t bevy_rs_query_entity_at(const BridgeQuery *query, int32_t index);

typedef struct bevy_world {
    void (*finalize)(struct bevy_world *);
    BridgeWorld *rust;
} bevy_world;

typedef struct bevy_query {
    void (*finalize)(struct bevy_query *);
    BridgeQuery *rust;
} bevy_query;

typedef struct bevy_hl_root {
    vdynamic *value;
} bevy_hl_root;

#define _BEVY_WORLD _ABSTRACT(bevy_world)
#define _BEVY_QUERY _ABSTRACT(bevy_query)

static void bevy_world_finalize(bevy_world *world) {
    if (world != NULL && world->rust != NULL) {
        bevy_rs_world_free(world->rust);
        world->rust = NULL;
    }
}

static void bevy_query_finalize(bevy_query *query) {
    if (query != NULL && query->rust != NULL) {
        bevy_rs_query_free(query->rust);
        query->rust = NULL;
    }
}

static bevy_hl_root *bevy_hl_root_create(vdynamic *value) {
    bevy_hl_root *root = (bevy_hl_root *)malloc(sizeof(bevy_hl_root));
    if (root == NULL) {
        return NULL;
    }
    root->value = value;
    hl_add_root(&root->value);
    return root;
}

/* Called by the Rust component drop function. */
HL_EXPORT void bevy_hl_root_release(void *opaque) {
    bevy_hl_root *root = (bevy_hl_root *)opaque;
    if (root != NULL) {
        hl_remove_root(&root->value);
        root->value = NULL;
        free(root);
    }
}

HL_PRIM int HL_NAME(bridge_version)(void) {
    return (int)bevy_rs_bridge_version();
}

HL_PRIM bevy_world *HL_NAME(world_new)(void) {
    bevy_world *world = (bevy_world *)hl_gc_alloc_finalizer(sizeof(bevy_world));
    world->finalize = bevy_world_finalize;
    world->rust = bevy_rs_world_new();
    return world;
}

HL_PRIM void HL_NAME(world_close)(bevy_world *world) {
    bevy_world_finalize(world);
}

HL_PRIM int HL_NAME(component_register)(bevy_world *world, int bridge_id, vstring *name, bool sparse) {
    if (world == NULL || world->rust == NULL || bridge_id < 0 || name == NULL) {
        return -1;
    }
    return bevy_rs_component_register(
        world->rust,
        (uint32_t)bridge_id,
        hl_to_utf8(name->bytes),
        sparse
    );
}

HL_PRIM int HL_NAME(spawn)(bevy_world *world) {
    if (world == NULL || world->rust == NULL) {
        return -1;
    }
    return (int)bevy_rs_spawn(world->rust);
}

HL_PRIM bool HL_NAME(entity_exists)(bevy_world *world, int entity) {
    return world != NULL && world->rust != NULL
        && bevy_rs_entity_exists(world->rust, (uint32_t)entity);
}

HL_PRIM int HL_NAME(entity_generation)(bevy_world *world, int entity) {
    if (world == NULL || world->rust == NULL) {
        return -1;
    }
    return (int)bevy_rs_entity_generation(world->rust, (uint32_t)entity);
}

HL_PRIM bool HL_NAME(despawn)(bevy_world *world, int entity) {
    return world != NULL && world->rust != NULL
        && bevy_rs_despawn(world->rust, (uint32_t)entity);
}

HL_PRIM bool HL_NAME(component_insert)(
    bevy_world *world,
    int entity,
    int component,
    vdynamic *value
) {
    bevy_hl_root *root;
    bool inserted;
    if (world == NULL || world->rust == NULL || component < 0 || value == NULL) {
        return false;
    }
    root = bevy_hl_root_create(value);
    if (root == NULL) {
        return false;
    }
    inserted = bevy_rs_component_insert(
        world->rust,
        (uint32_t)entity,
        (uint32_t)component,
        root
    );
    if (!inserted) {
        bevy_hl_root_release(root);
    }
    return inserted;
}

HL_PRIM vdynamic *HL_NAME(component_get)(bevy_world *world, int entity, int component) {
    bevy_hl_root *root;
    if (world == NULL || world->rust == NULL || component < 0) {
        return NULL;
    }
    root = (bevy_hl_root *)bevy_rs_component_get(
        world->rust,
        (uint32_t)entity,
        (uint32_t)component
    );
    return root == NULL ? NULL : root->value;
}

HL_PRIM bool HL_NAME(component_has)(bevy_world *world, int entity, int component) {
    return world != NULL && world->rust != NULL && component >= 0
        && bevy_rs_component_has(world->rust, (uint32_t)entity, (uint32_t)component);
}

HL_PRIM bool HL_NAME(component_remove)(bevy_world *world, int entity, int component) {
    return world != NULL && world->rust != NULL && component >= 0
        && bevy_rs_component_remove(world->rust, (uint32_t)entity, (uint32_t)component);
}

HL_PRIM bevy_query *HL_NAME(query_new)(bevy_world *world, varray *required, varray *excluded) {
    bevy_query *query;
    const uint32_t *required_data;
    const uint32_t *excluded_data;
    int required_len;
    int excluded_len;
    if (world == NULL || world->rust == NULL || required == NULL || excluded == NULL) {
        return NULL;
    }
    required_len = required->size;
    excluded_len = excluded->size;
    required_data = (const uint32_t *)hl_aptr(required, int);
    excluded_data = (const uint32_t *)hl_aptr(excluded, int);

    query = (bevy_query *)hl_gc_alloc_finalizer(sizeof(bevy_query));
    query->finalize = bevy_query_finalize;
    query->rust = bevy_rs_query_new(
        world->rust,
        required_data,
        (size_t)required_len,
        excluded_data,
        (size_t)excluded_len
    );
    if (query->rust == NULL) {
        query->finalize = NULL;
        return NULL;
    }
    return query;
}

HL_PRIM void HL_NAME(query_close)(bevy_query *query) {
    bevy_query_finalize(query);
}

HL_PRIM bool HL_NAME(query_refresh)(bevy_world *world, bevy_query *query) {
    return world != NULL && world->rust != NULL
        && query != NULL && query->rust != NULL
        && bevy_rs_query_refresh(world->rust, query->rust);
}

HL_PRIM int HL_NAME(query_fill_values)(
    bevy_world *world,
    bevy_query *query,
    int index,
    varray *out
) {
    if (world == NULL || world->rust == NULL
        || query == NULL || query->rust == NULL || out == NULL) {
        return -1;
    }
    return (int)bevy_rs_query_fill_values(
        world->rust,
        query->rust,
        index,
        (void **)hl_aptr(out, vdynamic *),
        (size_t)out->size
    );
}

HL_PRIM int HL_NAME(query_len)(bevy_query *query) {
    return query == NULL || query->rust == NULL ? 0 : bevy_rs_query_len(query->rust);
}

HL_PRIM int HL_NAME(query_entity_at)(bevy_query *query, int index) {
    return query == NULL || query->rust == NULL
        ? -1
        : (int)bevy_rs_query_entity_at(query->rust, index);
}

DEFINE_PRIM(_I32, bridge_version, _NO_ARG);
DEFINE_PRIM(_BEVY_WORLD, world_new, _NO_ARG);
DEFINE_PRIM(_VOID, world_close, _BEVY_WORLD);
DEFINE_PRIM(_I32, component_register, _BEVY_WORLD _I32 _STRING _BOOL);
DEFINE_PRIM(_I32, spawn, _BEVY_WORLD);
DEFINE_PRIM(_BOOL, entity_exists, _BEVY_WORLD _I32);
DEFINE_PRIM(_I32, entity_generation, _BEVY_WORLD _I32);
DEFINE_PRIM(_BOOL, despawn, _BEVY_WORLD _I32);
DEFINE_PRIM(_BOOL, component_insert, _BEVY_WORLD _I32 _I32 _DYN);
DEFINE_PRIM(_DYN, component_get, _BEVY_WORLD _I32 _I32);
DEFINE_PRIM(_BOOL, component_has, _BEVY_WORLD _I32 _I32);
DEFINE_PRIM(_BOOL, component_remove, _BEVY_WORLD _I32 _I32);
DEFINE_PRIM(_BEVY_QUERY, query_new, _BEVY_WORLD _ARR _ARR);
DEFINE_PRIM(_VOID, query_close, _BEVY_QUERY);
DEFINE_PRIM(_BOOL, query_refresh, _BEVY_WORLD _BEVY_QUERY);
DEFINE_PRIM(_I32, query_fill_values, _BEVY_WORLD _BEVY_QUERY _I32 _ARR);
DEFINE_PRIM(_I32, query_len, _BEVY_QUERY);
DEFINE_PRIM(_I32, query_entity_at, _BEVY_QUERY _I32);
