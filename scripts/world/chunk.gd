extends Node3D
class_name Chunk

## A single chunk of the voxel world.
## Stores block data in a flat array, generates mesh using greedy meshing.
## Each chunk is CHUNK_SIZE^3 voxels.

const CHUNK_SIZE: int = 32
const CHUNK_VOLUME: int = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

# Block data — flat array indexed by x + z * CHUNK_SIZE + y * CHUNK_SIZE * CHUNK_SIZE
var blocks: PackedInt32Array
var chunk_position: Vector3i  # Position in chunk coordinates (not world)
var is_dirty: bool = true  # Needs remeshing
var is_generated: bool = false
var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D
var transparent_mesh_instance: MeshInstance3D  # Separate pass for transparent blocks

# Neighbor references for seamless meshing across boundaries
var neighbor_px: Chunk  # +X
var neighbor_nx: Chunk  # -X
var neighbor_pz: Chunk  # +Z
var neighbor_nz: Chunk  # -Z
var neighbor_py: Chunk  # +Y
var neighbor_ny: Chunk  # -Y

func _init(pos: Vector3i = Vector3i.ZERO) -> void:
	chunk_position = pos
	blocks = PackedInt32Array()
	blocks.resize(CHUNK_VOLUME)
	blocks.fill(VoxelData.BlockID.AIR)

func _ready() -> void:
	position = Vector3(
		chunk_position.x * CHUNK_SIZE,
		chunk_position.y * CHUNK_SIZE,
		chunk_position.z * CHUNK_SIZE,
	)

	# Opaque mesh
	mesh_instance = MeshInstance3D.new()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(mesh_instance)

	# Transparent mesh (separate render pass)
	transparent_mesh_instance = MeshInstance3D.new()
	transparent_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	transparent_mesh_instance.transparency = 0.5
	add_child(transparent_mesh_instance)

	# Collision
	collision_body = StaticBody3D.new()
	collision_shape = CollisionShape3D.new()
	collision_body.add_child(collision_shape)
	add_child(collision_body)

# ── Block access ───────────────────────────────────────────────

func _index(x: int, y: int, z: int) -> int:
	return x + z * CHUNK_SIZE + y * CHUNK_SIZE * CHUNK_SIZE

func get_block(x: int, y: int, z: int) -> int:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE:
		return _get_neighbor_block(x, y, z)
	return blocks[_index(x, y, z)]

func set_block(x: int, y: int, z: int, block_id: int) -> void:
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_SIZE or z < 0 or z >= CHUNK_SIZE:
		return
	blocks[_index(x, y, z)] = block_id
	is_dirty = true

func _get_neighbor_block(x: int, y: int, z: int) -> int:
	# Sample from neighboring chunk for seamless meshing
	if x < 0 and neighbor_nx:
		return neighbor_nx.get_block(x + CHUNK_SIZE, y, z)
	if x >= CHUNK_SIZE and neighbor_px:
		return neighbor_px.get_block(x - CHUNK_SIZE, y, z)
	if y < 0 and neighbor_ny:
		return neighbor_ny.get_block(x, y + CHUNK_SIZE, z)
	if y >= CHUNK_SIZE and neighbor_py:
		return neighbor_py.get_block(x, y - CHUNK_SIZE, z)
	if z < 0 and neighbor_nz:
		return neighbor_nz.get_block(x, y, z + CHUNK_SIZE)
	if z >= CHUNK_SIZE and neighbor_pz:
		return neighbor_pz.get_block(x, y, z - CHUNK_SIZE)
	return VoxelData.BlockID.AIR  # Outside world = air

func get_block_world(world_pos: Vector3i) -> int:
	var local := world_pos - chunk_position * CHUNK_SIZE
	return get_block(local.x, local.y, local.z)

func set_block_world(world_pos: Vector3i, block_id: int) -> void:
	var local := world_pos - chunk_position * CHUNK_SIZE
	set_block(local.x, local.y, local.z, block_id)

# ── Mesh Generation (Greedy Meshing) ──────────────────────────

func build_mesh() -> void:
	if not is_dirty:
		return

	var opaque_verts := PackedVector3Array()
	var opaque_normals := PackedVector3Array()
	var opaque_colors := PackedColorArray()
	var opaque_uvs := PackedVector2Array()

	var trans_verts := PackedVector3Array()
	var trans_normals := PackedVector3Array()
	var trans_colors := PackedColorArray()
	var trans_uvs := PackedVector2Array()

	# Iterate each axis for greedy meshing
	for axis in 3:
		_greedy_mesh_axis(
			axis, opaque_verts, opaque_normals, opaque_colors, opaque_uvs,
			trans_verts, trans_normals, trans_colors, trans_uvs
		)

	# Build opaque mesh
	if opaque_verts.size() > 0:
		var arr_mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = opaque_verts
		arrays[Mesh.ARRAY_NORMAL] = opaque_normals
		arrays[Mesh.ARRAY_COLOR] = opaque_colors
		arrays[Mesh.ARRAY_TEX_UV] = opaque_uvs
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh_instance.mesh = arr_mesh
		# Generate collision from opaque mesh
		collision_shape.shape = arr_mesh.create_trimesh_shape()
	else:
		mesh_instance.mesh = null
		collision_shape.shape = null

	# Build transparent mesh
	if trans_verts.size() > 0:
		var trans_mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = trans_verts
		arrays[Mesh.ARRAY_NORMAL] = trans_normals
		arrays[Mesh.ARRAY_COLOR] = trans_colors
		arrays[Mesh.ARRAY_TEX_UV] = trans_uvs
		trans_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		transparent_mesh_instance.mesh = trans_mesh
	else:
		transparent_mesh_instance.mesh = null

	is_dirty = false

func _greedy_mesh_axis(
	axis: int,
	o_verts: PackedVector3Array, o_normals: PackedVector3Array,
	o_colors: PackedColorArray, o_uvs: PackedVector2Array,
	t_verts: PackedVector3Array, t_normals: PackedVector3Array,
	t_colors: PackedColorArray, t_uvs: PackedVector2Array,
) -> void:
	# Axes: 0=X, 1=Y, 2=Z
	# For each slice along the axis, build a 2D mask of exposed faces,
	# then merge adjacent same-type faces into larger quads.

	var u_axis := (axis + 1) % 3  # First tangent axis
	var v_axis := (axis + 2) % 3  # Second tangent axis
	var normal := Vector3.ZERO
	var size := Vector3i(CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)

	for facing in 2:  # 0 = negative face, 1 = positive face
		normal = Vector3.ZERO
		normal[axis] = 1.0 if facing == 1 else -1.0

		# For each slice along the axis
		for d in range(CHUNK_SIZE):
			# Build face mask — which positions need a face?
			var mask: Array[int] = []  # block_id or -1
			mask.resize(CHUNK_SIZE * CHUNK_SIZE)
			mask.fill(-1)

			for v in CHUNK_SIZE:
				for u in CHUNK_SIZE:
					var pos := Vector3i.ZERO
					pos[axis] = d
					pos[u_axis] = u
					pos[v_axis] = v

					var block_id := get_block(pos.x, pos.y, pos.z)
					if block_id == VoxelData.BlockID.AIR:
						continue

					# Check neighbor in normal direction
					var neighbor_pos := pos
					neighbor_pos[axis] += 1 if facing == 1 else -1
					var neighbor_id := get_block(neighbor_pos.x, neighbor_pos.y, neighbor_pos.z)

					var block_solid := VoxelData.is_solid(block_id)
					var neighbor_solid := VoxelData.is_solid(neighbor_id)
					var block_transparent := VoxelData.is_transparent(block_id)
					var neighbor_transparent := VoxelData.is_transparent(neighbor_id)

					# Face is visible if neighbor is air/transparent and we are solid,
					# or if we are transparent and neighbor is air
					var face_visible := false
					if block_solid and not block_transparent:
						face_visible = not neighbor_solid or neighbor_transparent
					elif block_transparent and block_id != VoxelData.BlockID.AIR:
						face_visible = neighbor_id == VoxelData.BlockID.AIR

					if face_visible:
						mask[u + v * CHUNK_SIZE] = block_id

			# Greedy merge — scan mask, merge adjacent same-type into quads
			var visited: Array[bool] = []
			visited.resize(CHUNK_SIZE * CHUNK_SIZE)
			visited.fill(false)

			for v in CHUNK_SIZE:
				for u in CHUNK_SIZE:
					var idx := u + v * CHUNK_SIZE
					if visited[idx] or mask[idx] == -1:
						continue

					var block_id := mask[idx]
					var is_transparent := VoxelData.is_transparent(block_id)

					# Expand width (u direction)
					var width := 1
					while u + width < CHUNK_SIZE:
						var next_idx := (u + width) + v * CHUNK_SIZE
						if visited[next_idx] or mask[next_idx] != block_id:
							break
						width += 1

					# Expand height (v direction)
					var height := 1
					var can_expand := true
					while v + height < CHUNK_SIZE and can_expand:
						for w in width:
							var check_idx := (u + w) + (v + height) * CHUNK_SIZE
							if visited[check_idx] or mask[check_idx] != block_id:
								can_expand = false
								break
						if can_expand:
							height += 1

					# Mark visited
					for vv in height:
						for uu in width:
							visited[(u + uu) + (v + vv) * CHUNK_SIZE] = true

					# Emit quad
					var origin := Vector3.ZERO
					origin[axis] = float(d) + (1.0 if facing == 1 else 0.0)
					origin[u_axis] = float(u)
					origin[v_axis] = float(v)

					var du := Vector3.ZERO
					du[u_axis] = float(width)

					var dv := Vector3.ZERO
					dv[v_axis] = float(height)

					var color := VoxelData.get_color(block_id)

					# Pick target arrays
					var verts := t_verts if is_transparent else o_verts
					var normals := t_normals if is_transparent else o_normals
					var colors := t_colors if is_transparent else o_colors
					var uvs := t_uvs if is_transparent else o_uvs

					if facing == 1:
						# Positive face — CCW winding
						_emit_quad(verts, normals, colors, uvs,
							origin, origin + du, origin + du + dv, origin + dv,
							normal, color, Vector2(width, height))
					else:
						# Negative face — reverse winding
						_emit_quad(verts, normals, colors, uvs,
							origin, origin + dv, origin + du + dv, origin + du,
							normal, color, Vector2(width, height))

func _emit_quad(
	verts: PackedVector3Array, normals: PackedVector3Array,
	colors: PackedColorArray, uvs: PackedVector2Array,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3, color: Color, uv_scale: Vector2,
) -> void:
	# Triangle 1: a, b, c
	verts.append(a)
	verts.append(b)
	verts.append(c)
	# Triangle 2: a, c, d
	verts.append(a)
	verts.append(c)
	verts.append(d)

	for i in 6:
		normals.append(normal)
		colors.append(color)

	# UVs scaled by quad size for tiling textures
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(uv_scale.x, 0))
	uvs.append(Vector2(uv_scale.x, uv_scale.y))
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(uv_scale.x, uv_scale.y))
	uvs.append(Vector2(0, uv_scale.y))

# ── Destruction ────────────────────────────────────────────────

func destroy_block(x: int, y: int, z: int) -> int:
	var block_id := get_block(x, y, z)
	if block_id == VoxelData.BlockID.AIR or block_id == VoxelData.BlockID.BEDROCK:
		return VoxelData.BlockID.AIR
	set_block(x, y, z, VoxelData.BlockID.AIR)
	# Flag neighbors as dirty too (for seamless mesh updates)
	if x == 0 and neighbor_nx: neighbor_nx.is_dirty = true
	if x == CHUNK_SIZE - 1 and neighbor_px: neighbor_px.is_dirty = true
	if y == 0 and neighbor_ny: neighbor_ny.is_dirty = true
	if y == CHUNK_SIZE - 1 and neighbor_py: neighbor_py.is_dirty = true
	if z == 0 and neighbor_nz: neighbor_nz.is_dirty = true
	if z == CHUNK_SIZE - 1 and neighbor_pz: neighbor_pz.is_dirty = true
	return block_id

func explosion(center: Vector3i, radius: int) -> Array[Dictionary]:
	"""Destroy blocks in a sphere. Returns destroyed block info for debris spawning."""
	var destroyed: Array[Dictionary] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if x * x + y * y + z * z <= radius * radius:
					var bx := center.x + x
					var by := center.y + y
					var bz := center.z + z
					if bx >= 0 and bx < CHUNK_SIZE and by >= 0 and by < CHUNK_SIZE and bz >= 0 and bz < CHUNK_SIZE:
						var block_id := destroy_block(bx, by, bz)
						if block_id != VoxelData.BlockID.AIR:
							destroyed.append({
								"block_id": block_id,
								"position": Vector3(bx, by, bz) + position,
							})
	return destroyed
