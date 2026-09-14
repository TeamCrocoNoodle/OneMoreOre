extends SceneTree
const B = preload("res://scripts/game_balance.gd")
const S = preload("res://scripts/skill_tree.gd")
const Effects = preload("res://scripts/skill_balance.gd")
const M = preload("res://scripts/main_tools.gd")
const A = preload("res://scripts/aux_tools.gd")
const O = preload("res://scripts/ore_progression.gd")
const Boss = preload("res://scripts/boss_campaign.gd")

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/balance")
	var skills := S.new()
	var total := 0
	var csv := FileAccess.open("res://docs/balance/skills.csv",FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["id","name","category","depth","gold","effects","description"]))
	for node in skills.get_nodes():
		total += int(node.cost)
		skills._owned[node.id] = true
		csv.store_csv_line(PackedStringArray([node.id,node.title,node.category,str(node.depth),str(node.cost),JSON.stringify(node.effects),node.description]))
	csv.close()
	var main := M.new()
	main.acquire("gold_pickaxe",B.MAIN_PRICES[-1])
	var aux := A.new()
	var auxiliary_cost := 0
	for entry in A.CATALOG:
		aux.acquire(entry.id,entry.price)
		auxiliary_cost += int(entry.price)
	var ores: Array[Dictionary] = []
	for stage in 7: ores.append(O.profile(B.ORE_GOLD[stage],stage))
	var output := {"version":"2026-09-14-v2","skill_effects":Effects.VALUES,"skill_depth_costs":B.SKILL_DEPTH_COSTS,"skill_premiums":B.SKILL_PREMIUMS,"total_skill_gold":total,"total_final_build_gold":total+auxiliary_cost+B.MAIN_PRICES[-1],"main_tools":M.CATALOG,"aux_tools":A.CATALOG,"gem_gold":B.GEM_GOLD,"ores":ores,"bosses":Boss.BOSSES,"full_build":aux.apply_to(main.apply_to(skills.stats())),"recovery_budget_fraction":B.RECOVERY_BUDGET,"crusher_cooldown":A.CRUSHER_COOLDOWN,"crusher_work":B.CRUSHER_WORK,"detonator_work":B.DETONATOR_WORK,"bomb_armor_fraction":B.BOMB_ARMOR_FRACTION,"laser_interval":[A.LASER_MIN,A.LASER_MAX],"beer_health":A.BEER_HEALTH,"pin_chance":A.PIN_CHANCE,"pin_radius":A.PIN_RADIUS}
	var file := FileAccess.open("res://docs/balance/values.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	print("BALANCE_EXPORT_OK tree=",total," final_build=",output.total_final_build_gold)
	quit()
