extends GutTest
## Дымовой тест: проверяет, что GUT запускается и проект загружается.


func test_gut_runs() -> void:
	assert_true(true, "GUT выполняет тесты")


func test_arithmetic() -> void:
	var a: int = 2
	var b: int = 3
	assert_eq(a + b, 5, "2 + 3 == 5")


func test_project_name() -> void:
	var project_name: String = ProjectSettings.get_setting("application/config/name")
	assert_eq(project_name, "DeskHero")
