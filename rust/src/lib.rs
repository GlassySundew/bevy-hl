//! Bevy ECS core for the HashLink bridge.
//!
//! HashLink values remain owned and rooted by `bevy_hl.c`. Bevy stores only
//! stable root-slot addresses as opaque, pointer-sized dynamic components.

use std::{
    alloc::Layout,
    ffi::{CStr, c_char, c_void},
};

use bevy_ecs::{
    component::{ComponentCloneBehavior, ComponentDescriptor, ComponentId, StorageType},
    entity::Entity,
    prelude::World,
    ptr::OwningPtr,
    query::{QueryBuilder, QueryState},
};

pub const BRIDGE_VERSION: u32 = 4;

#[cfg(not(test))]
unsafe extern "C" {
    fn bevy_hl_root_release(root: *mut c_void);
}

#[cfg(test)]
unsafe fn bevy_hl_root_release(_root: *mut c_void) {}

unsafe fn drop_haxe_root(ptr: OwningPtr<'_>) {
    // SAFETY: Every dynamic component registered by this bridge has the exact
    // layout of a single root-slot pointer and is inserted from the same type.
    let root = unsafe { ptr.read::<*mut c_void>() };
    if !root.is_null() {
        // SAFETY: The slot was allocated and rooted by bevy_hl_root_create and
        // ownership was transferred to this component.
        unsafe { bevy_hl_root_release(root) };
    }
}

pub struct BridgeWorld {
    world: World,
    component_ids: Vec<Option<ComponentId>>,
    component_descriptors: Vec<Option<(String, bool)>>,
    entities: std::collections::HashMap<u32, Entity>,
    entity_handles: std::collections::HashMap<Entity, u32>,
    next_entity_handle: u32,
}

impl BridgeWorld {
    fn new() -> Self {
        Self {
            world: World::new(),
            component_ids: Vec::new(),
            component_descriptors: Vec::new(),
            entities: std::collections::HashMap::new(),
            entity_handles: std::collections::HashMap::new(),
            next_entity_handle: 1,
        }
    }

    fn component_id(&self, raw: u32) -> Option<ComponentId> {
        self.component_ids.get(raw as usize).copied().flatten()
    }

    fn entity(&self, handle: u32) -> Option<Entity> {
        self.entities.get(&handle).copied()
    }
}

pub struct BridgeQuery {
    state: QueryState<Entity>,
    required: Vec<ComponentId>,
    entities: Vec<u32>,
}

fn refresh_query(world: &BridgeWorld, query: &mut BridgeQuery) {
    query.state.update_archetypes(&world.world);
    query.entities.clear();
    query.entities.extend(
        query
            .state
            .iter(&world.world)
            .filter_map(|entity| world.entity_handles.get(&entity).copied()),
    );
}

fn world_mut<'a>(world: *mut BridgeWorld) -> Option<&'a mut BridgeWorld> {
    // SAFETY: All callers are serialized on the HashLink thread. The C wrapper
    // owns the Box and nulls its pointer on disposal.
    unsafe { world.as_mut() }
}

#[unsafe(no_mangle)]
pub extern "C" fn bevy_rs_bridge_version() -> u32 {
    BRIDGE_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn bevy_rs_world_new() -> *mut BridgeWorld {
    Box::into_raw(Box::new(BridgeWorld::new()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_world_free(world: *mut BridgeWorld) {
    if !world.is_null() {
        // SAFETY: Ownership came from Box::into_raw in bevy_rs_world_new and
        // the C wrapper guarantees this is called once.
        drop(unsafe { Box::from_raw(world) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_component_register(
    world: *mut BridgeWorld,
    bridge_id: u32,
    name: *const c_char,
    sparse: bool,
) -> i32 {
    let Some(world) = world_mut(world) else {
        return -1;
    };
    if name.is_null() {
        return -1;
    }

    // SAFETY: The C wrapper passes a temporary NUL-terminated UTF-8 string.
    let Ok(name) = unsafe { CStr::from_ptr(name) }.to_str() else {
        return -1;
    };
    if world.component_id(bridge_id).is_some() {
        let existing_matches = world
            .component_descriptors
            .get(bridge_id as usize)
            .and_then(Option::as_ref)
            .is_some_and(|(existing_name, existing_sparse)| {
                existing_name == name && *existing_sparse == sparse
            });
        return if existing_matches {
            bridge_id as i32
        } else {
            -2
        };
    }

    let storage = if sparse {
        StorageType::SparseSet
    } else {
        StorageType::Table
    };
    // SAFETY: The stored value is a pointer-sized opaque token. Moving or
    // reading the token itself is Send + Sync; the bridge dereferences the
    // corresponding HashLink value only on the owning HashLink thread.
    let descriptor = unsafe {
        ComponentDescriptor::new_with_layout(
            name.to_owned(),
            storage,
            Layout::new::<*mut c_void>(),
            Some(drop_haxe_root),
            true,
            ComponentCloneBehavior::Ignore,
            None,
        )
    };
    let id = world.world.register_component_with_descriptor(descriptor);
    let required_len = bridge_id as usize + 1;
    if world.component_ids.len() < required_len {
        world.component_ids.resize(required_len, None);
        world.component_descriptors.resize(required_len, None);
    }
    world.component_ids[bridge_id as usize] = Some(id);
    world.component_descriptors[bridge_id as usize] = Some((name.to_owned(), sparse));
    bridge_id as i32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_spawn(world: *mut BridgeWorld) -> u32 {
    let Some(world) = world_mut(world) else {
        return u32::MAX;
    };
    let entity = world.world.spawn_empty().id();
    let handle = world.next_entity_handle;
    world.next_entity_handle = world.next_entity_handle.checked_add(1).unwrap_or(1);
    world.entities.insert(handle, entity);
    world.entity_handles.insert(entity, handle);
    handle
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_entity_exists(world: *mut BridgeWorld, handle: u32) -> bool {
    let Some(world) = world_mut(world) else {
        return false;
    };
    let Some(entity) = world.entity(handle) else {
        return false;
    };
    world.world.get_entity(entity).is_ok()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_entity_generation(world: *mut BridgeWorld, handle: u32) -> u32 {
    let Some(world) = world_mut(world) else {
        return u32::MAX;
    };
    let Some(entity) = world.entity(handle) else {
        return u32::MAX;
    };
    if world.world.get_entity(entity).is_err() {
        return u32::MAX;
    }
    entity.generation().to_bits()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_despawn(world: *mut BridgeWorld, handle: u32) -> bool {
    let Some(world) = world_mut(world) else {
        return false;
    };
    let Some(entity) = world.entities.remove(&handle) else {
        return false;
    };
    world.entity_handles.remove(&entity);
    world.world.despawn(entity)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_component_insert(
    world: *mut BridgeWorld,
    handle: u32,
    component: u32,
    root: *mut c_void,
) -> bool {
    let Some(world) = world_mut(world) else {
        return false;
    };
    let (Some(entity), Some(component)) = (world.entity(handle), world.component_id(component))
    else {
        return false;
    };
    let Ok(mut entity_mut) = world.world.get_entity_mut(entity) else {
        return false;
    };

    OwningPtr::make(root, |ptr| {
        // SAFETY: component was registered by this bridge with pointer layout,
        // belongs to this world, and ptr points to that exact pointer value.
        unsafe { entity_mut.insert_by_id(component, ptr) };
    });
    true
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_component_get(
    world: *mut BridgeWorld,
    handle: u32,
    component: u32,
) -> *mut c_void {
    let Some(world) = world_mut(world) else {
        return std::ptr::null_mut();
    };
    let (Some(entity), Some(component)) = (world.entity(handle), world.component_id(component))
    else {
        return std::ptr::null_mut();
    };
    let Some(ptr) = world.world.get_by_id(entity, component) else {
        return std::ptr::null_mut();
    };
    // SAFETY: Components registered through this bridge always contain a
    // root-slot pointer with this exact layout.
    unsafe { *ptr.deref::<*mut c_void>() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_component_has(
    world: *mut BridgeWorld,
    handle: u32,
    component: u32,
) -> bool {
    !unsafe { bevy_rs_component_get(world, handle, component) }.is_null()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_component_remove(
    world: *mut BridgeWorld,
    handle: u32,
    component: u32,
) -> bool {
    let Some(world) = world_mut(world) else {
        return false;
    };
    let (Some(entity), Some(component)) = (world.entity(handle), world.component_id(component))
    else {
        return false;
    };
    let Ok(mut entity_mut) = world.world.get_entity_mut(entity) else {
        return false;
    };
    if entity_mut.get_by_id(component).is_err() {
        return false;
    }
    entity_mut.remove_by_id(component);
    true
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_query_new(
    world: *mut BridgeWorld,
    required: *const u32,
    required_len: usize,
    excluded: *const u32,
    excluded_len: usize,
) -> *mut BridgeQuery {
    let Some(world) = world_mut(world) else {
        return std::ptr::null_mut();
    };
    if (required_len > 0 && required.is_null()) || (excluded_len > 0 && excluded.is_null()) {
        return std::ptr::null_mut();
    }
    // SAFETY: C passes arrays containing at least the supplied lengths.
    let required = unsafe { std::slice::from_raw_parts(required, required_len) };
    // SAFETY: Same as above.
    let excluded = unsafe { std::slice::from_raw_parts(excluded, excluded_len) };

    let Some(required): Option<Vec<_>> =
        required.iter().map(|id| world.component_id(*id)).collect()
    else {
        return std::ptr::null_mut();
    };
    let Some(excluded): Option<Vec<_>> =
        excluded.iter().map(|id| world.component_id(*id)).collect()
    else {
        return std::ptr::null_mut();
    };

    let mut builder = QueryBuilder::<Entity>::new(&mut world.world);
    for id in &required {
        builder.with_id(*id);
    }
    for id in excluded {
        builder.without_id(id);
    }
    let state = builder.build();
    let mut query = BridgeQuery {
        state,
        required,
        entities: Vec::new(),
    };
    refresh_query(world, &mut query);
    Box::into_raw(Box::new(query))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_query_fill_values(
    world: *mut BridgeWorld,
    query: *const BridgeQuery,
    index: i32,
    out: *mut *mut c_void,
    out_len: usize,
) -> u32 {
    if index < 0 {
        return u32::MAX;
    }
    let (Some(world), Some(query)) = (world_mut(world), unsafe { query.as_ref() }) else {
        return u32::MAX;
    };
    if out_len != query.required.len() || (out_len > 0 && out.is_null()) {
        return u32::MAX;
    }
    let Some(handle) = query.entities.get(index as usize).copied() else {
        return u32::MAX;
    };
    let Some(entity) = world.entity(handle) else {
        return u32::MAX;
    };
    // SAFETY: The C wrapper passes a HashLink dynamic array with exactly
    // `out_len` pointer slots. Component roots are C structs whose first and
    // only field is the rooted HashLink value pointer.
    let values = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    for (slot, component) in values.iter_mut().zip(&query.required) {
        let Some(ptr) = world.world.get_by_id(entity, *component) else {
            return u32::MAX;
        };
        let root = unsafe { *ptr.deref::<*mut c_void>() };
        *slot = if root.is_null() {
            std::ptr::null_mut()
        } else {
            unsafe { *(root as *mut *mut c_void) }
        };
    }
    handle
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_query_refresh(
    world: *mut BridgeWorld,
    query: *mut BridgeQuery,
) -> bool {
    let (Some(world), Some(query)) = (world_mut(world), unsafe { query.as_mut() }) else {
        return false;
    };
    refresh_query(world, query);
    true
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_query_free(query: *mut BridgeQuery) {
    if !query.is_null() {
        // SAFETY: The pointer originated from Box::into_raw above and the C
        // wrapper releases it at most once.
        drop(unsafe { Box::from_raw(query) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_query_len(query: *const BridgeQuery) -> i32 {
    // SAFETY: The C wrapper owns the query while calling this function.
    unsafe { query.as_ref() }
        .map(|query| query.entities.len().min(i32::MAX as usize) as i32)
        .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn bevy_rs_query_entity_at(query: *const BridgeQuery, index: i32) -> u32 {
    if index < 0 {
        return u32::MAX;
    }
    // SAFETY: The C wrapper owns the query while calling this function.
    unsafe { query.as_ref() }
        .and_then(|query| query.entities.get(index as usize).copied())
        .unwrap_or(u32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn spawned_entity_round_trips_through_bits() {
        let mut bridge = BridgeWorld::new();
        let entity = bridge.world.spawn_empty().id();
        assert_ne!(entity.to_bits(), u64::MAX);
        assert_eq!(Entity::try_from_bits(entity.to_bits()), Some(entity));
        assert!(bridge.world.get_entity(entity).is_ok());
    }

    #[test]
    fn bridge_handle_reports_live_generation_only() {
        let mut bridge = BridgeWorld::new();
        let bridge_ptr = &mut bridge as *mut BridgeWorld;
        let handle = unsafe { bevy_rs_spawn(bridge_ptr) };
        let generation = unsafe { bevy_rs_entity_generation(bridge_ptr, handle) };
        assert_ne!(generation, u32::MAX);
        assert!(unsafe { bevy_rs_despawn(bridge_ptr, handle) });
        assert_eq!(
            unsafe { bevy_rs_entity_generation(bridge_ptr, handle) },
            u32::MAX
        );
    }

    #[test]
    fn dense_bridge_component_id_maps_to_bevy_component_id() {
        let mut bridge = BridgeWorld::new();
        let bridge_ptr = &mut bridge as *mut BridgeWorld;
        let name = CString::new("test.Position").unwrap();
        let bridge_id = 7;
        assert_eq!(
            unsafe { bevy_rs_component_register(bridge_ptr, bridge_id, name.as_ptr(), false) },
            bridge_id as i32
        );
        assert!(bridge.component_id(bridge_id).is_some());
        assert!(bridge.component_id(0).is_none());
    }
}
