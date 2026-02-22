sv import from user {
    SaveUserProfile,
    GetUserProfile,
    ClearUserProfile,
    GenerateUserMacroNeeds
}

sv import from ingredient {
    GenerateRecipeFromPantry,
    ListGeneratedRecipe,
    ClearGeneratedRecipe,
    ParseReceiptTextToPantry
}

sv import from receipt {
    ExtractReceiptText
}

# Single-page test console for the full backend flow:
# create user -> persist user -> generate macros -> generate recipe -> update pantry.
def:pub app -> JsxElement {
    has status: str = "",
        loading: bool = false,
        user_profile: dict = {},
        macro_needs: dict = {},
        pantry: list = [],
        recipe: dict = {},
        receipt_parse: dict = {},
        last_error: dict = {},
        debug_events: list = [],
        show_debug: bool = true;

    has user_id: str = "",
        age: str = "",
        sex: str = "MALE",
        height: str = "",
        weight: str = "",
        dietary_restrictions_text: str = "",
        allergies_text: str = "",
        fitness_level: str = "MODERATELY_ACTIVE",
        goal: str = "MUSCLE_GAIN";

    has ing_name: str = "",
        ing_quantity: str = "1",
        ing_unit: str = "PIECE",
        ing_cost: str = "",
        ing_protein: str = "",
        ing_carb: str = "",
        ing_fat: str = "";

    has receipt_image_name: str = "",
        receipt_image_b64: str = "",
        receipt_ocr_text: str = "";

    has active_tab: str = "console",
        survey_user_id: str = "",
        survey_name: str = "",
        survey_age: str = "",
        survey_sex: str = "MALE",
        survey_height: str = "",
        survey_weight: str = "",
        survey_goal: str = "MUSCLE_GAIN",
        survey_fitness_level: str = "MODERATELY_ACTIVE",
        survey_cooking_days: str = "4",
        survey_meals_per_day: str = "3",
        survey_budget: str = "medium",
        survey_time_minutes: str = "30",
        survey_skill: str = "intermediate",
        survey_dietary_notes: str = "",
        survey_allergy_notes: str = "",
        survey_dislikes: str = "",
        survey_response: dict = {},
        survey_step: int = 0;

    # Parse numeric text inputs safely to prevent NaN payloads.
    def to_num(value: str, fallback: float = 0.0) -> float {
        parsed = parseFloat(value);
        if isNaN(parsed) {
            return fallback;
        }
        return parsed;
    }

    def is_int_str(value: str) -> bool {
        if not value.trim() {
            return false;
        }
        return not isNaN(parseInt(value));
    }

    def is_num_str(value: str) -> bool {
        if not value.trim() {
            return false;
        }
        return not isNaN(parseFloat(value));
    }

    # User IDs are generated automatically and kept numeric.
    def generate_user_id() -> str {
        now_obj = Reflect.construct(Date, []);
        epoch_text = now_obj.getTime().toString();
        rand_text = Math.floor(Math.random() * 1000).toString();
        return [epoch_text, rand_text].join("");
    }

    def ensure_user_id() -> None {
        if not is_int_str(user_id) {
            user_id = generate_user_id();
        }
        survey_user_id = user_id;
    }

    def normalize_int_text(value: str) -> str {
        trimmed = value.trim();
        if not trimmed {
            return "";
        }
        parsed = parseInt(trimmed);
        if isNaN(parsed) {
            return "";
        }
        return parsed.toString();
    }

    def split_csv(text: str) -> list {
        if not text.trim() {
            return [];
        }
        return text.split(",").map(
            lambda item: str -> str { return item.trim(); }
        ).filter(
            lambda item: str -> bool { return item.length > 0; }
        );
    }

    def build_survey_profile_payload() -> dict {
        ensure_user_id();
        norm_age = normalize_int_text(survey_age);
        if not norm_age {
            return {};
        }

        norm_height = to_num(survey_height, -1.0);
        norm_weight = to_num(survey_weight, -1.0);
        if norm_height < 0 or norm_weight < 0 {
            return {};
        }

        return {
            "user_id": parseInt(user_id),
            "age": parseInt(norm_age),
            "sex": survey_sex,
            "height": norm_height,
            "weight": norm_weight,
            "dietary_restrictions": split_csv(survey_dietary_notes),
            "allergies": split_csv(survey_allergy_notes),
            "fitness_level": survey_fitness_level,
            "goal": survey_goal
        };
    }

    def add_debug(event_type: str, context: str, payload: dict = {}) -> None {
        entry = {
            "time": Date().toString(),
            "type": event_type,
            "context": context,
            "payload": payload
        };
        debug_events = [entry].concat(debug_events);
        if debug_events.length > 50 {
            debug_events = debug_events.slice(0, 50);
        }
        if event_type == "error" {
            last_error = entry;
            console.error("CaloReceipt debug error", entry);
        } else {
            console.log("CaloReceipt debug", entry);
        }
    }

    def build_error_payload(context: str, err: any) -> dict {
        err_text = "";
        err_json = "";
        err_stack = "";

        try {
            err_text = err.toString();
        } except Exception as _e {
            err_text = "Unable to stringify error";
        }
        try {
            err_json = JSON.stringify(err, None, 2);
        } except Exception as _e {
            err_json = "Error object is not JSON-serializable";
        }
        try {
            err_stack = err.stack;
        } except Exception as _e {
            err_stack = "";
        }

        return {
            "context": context,
            "error_text": err_text,
            "error_json": err_json,
            "error_stack": err_stack
        };
    }

    # Build the server-facing profile payload from current form state.
    def build_profile() -> dict {
        return {
            "user_id": parseInt(user_id),
            "age": parseInt(age),
            "sex": sex,
            "height": to_num(height),
            "weight": to_num(weight),
            "dietary_restrictions": split_csv(dietary_restrictions_text),
            "allergies": split_csv(allergies_text),
            "fitness_level": fitness_level,
            "goal": goal
        };
    }

    # Local pantry editor helpers (frontend state only).
    def add_pantry_item() -> None {
        if not ing_name.trim() {
            status = "Ingredient name is required.";
            return;
        }

        pantry = pantry.concat([{
            "name": ing_name.trim(),
            "quantity": to_num(ing_quantity, 1.0),
            "unit": ing_unit,
            "cost": to_num(ing_cost, 0.0),
            "protein": to_num(ing_protein, 0.0),
            "carb": to_num(ing_carb, 0.0),
            "fat": to_num(ing_fat, 0.0)
        }]);

        ing_name = "";
        ing_quantity = "1";
        ing_unit = "PIECE";
        ing_cost = "0";
        ing_protein = "0";
        ing_carb = "0";
        ing_fat = "0";
        status = "Ingredient added to pantry.";
    }

    def remove_pantry_item(name: str) -> None {
        pantry = pantry.filter(
            lambda item: dict -> bool { return item.name != name; }
        );
    }

    # Merge parsed receipt items into pantry by lowercase name + unit.
    def merge_items_into_pantry(items: list) -> None {
        for new_item in items {
            merged = false;
            next_pantry: list = [];
            for existing in pantry {
                if (
                    existing.name.toLowerCase() == new_item.name.toLowerCase() and
                    existing.unit.toUpperCase() == new_item.unit.toUpperCase()
                ) {
                    next_pantry = next_pantry.concat([{
                        "name": existing.name,
                        "quantity": to_num(existing.quantity.toString()) + to_num(new_item.quantity.toString()),
                        "unit": existing.unit.toUpperCase(),
                        "cost": to_num(existing.cost.toString()) + to_num(new_item.cost.toString()),
                        "protein": to_num(existing.protein.toString()) + to_num(new_item.protein.toString()),
                        "carb": to_num(existing.carb.toString()) + to_num(new_item.carb.toString()),
                        "fat": to_num(existing.fat.toString()) + to_num(new_item.fat.toString())
                    }]);
                    merged = true;
                } else {
                    next_pantry = next_pantry.concat([existing]);
                }
            }
            if not merged {
                next_pantry = next_pantry.concat([{
                    "name": new_item.name,
                    "quantity": new_item.quantity,
                    "unit": new_item.unit.toUpperCase(),
                    "cost": new_item.cost,
                    "protein": new_item.protein,
                    "carb": new_item.carb,
                    "fat": new_item.fat
                }]);
            }
            pantry = next_pantry;
        }
    }

    # Read chosen receipt image into base64 for backend OCR walker.
    def on_receipt_image_change(e: any) -> None {
        files = e.target.files;
        if not files or files.length == 0 {
            receipt_image_name = "";
            receipt_image_b64 = "";
            return;
        }
        file = files[0];
        receipt_image_name = file.name;
        reader = Reflect.construct(FileReader, []);
        reader.onload = lambda ev: any -> None {
            data_url = ev.target.result;
            raw = data_url.split(",")[1];
            receipt_image_b64 = raw;
            status = "Receipt image loaded. Click OCR Import to add pantry items.";
        };
        reader.onerror = lambda _ev: any -> None {
            status = "Failed to read selected receipt image.";
            add_debug("error", "receipt.file_read_error", {"file_name": file.name});
        };
        reader.readAsDataURL(file);
    }

    # OCR receipt image, map text -> pantry ingredients (single LLM call), then merge to pantry.
    async def import_receipt_to_pantry -> None {
        if not receipt_image_b64 {
            status = "Select a receipt image first.";
            return;
        }

        loading = true;
        status = "Running OCR on receipt...";
        try {
            add_debug("request", "ExtractReceiptText", {
                "image_name": receipt_image_name,
                "is_base64": true,
                "languages": ["en"]
            });
            ocr_result = root spawn ExtractReceiptText(
                image_input=receipt_image_b64,
                is_base64=true,
                languages=["en"]
            );
            add_debug("response", "ExtractReceiptText", {"raw_result": ocr_result});
            ocr_out = ocr_result.reports[0];
            if not ocr_out.ok {
                status = "Receipt OCR failed: " + ocr_out.error;
                add_debug("error", "ExtractReceiptText.reported_error", {"ocr_out": ocr_out});
                loading = false;
                return;
            }

            receipt_ocr_text = ocr_out.text;
            status = "Parsing receipt food lines into pantry items...";
            add_debug("request", "ParseReceiptTextToPantry", {"receipt_text": receipt_ocr_text});
            parse_result = root spawn ParseReceiptTextToPantry(receipt_text=receipt_ocr_text);
            add_debug("response", "ParseReceiptTextToPantry", {"raw_result": parse_result});
            parse_out = parse_result.reports[0];
            receipt_parse = parse_out;
            if not parse_out.ok {
                status = "Receipt parse failed: " + parse_out.error;
                add_debug("error", "ParseReceiptTextToPantry.reported_error", {"parse_out": parse_out});
                loading = false;
                return;
            }

            merge_items_into_pantry(parse_out.items);
            status = "Receipt imported. Pantry updated with parsed items.";
        } except Exception as e {
            err_payload = build_error_payload("ReceiptImport.exception", e);
            add_debug("error", "ReceiptImport.exception", err_payload);
            status = "Receipt import failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # After recipe generation, subtract used quantities from local pantry inventory.
    def subtract_recipe_from_pantry(recipe_ingredients: list) -> None {
        updated_pantry: list = [];
        for pantry_item in pantry {
            used_qty: float = 0.0;
            for recipe_item in recipe_ingredients {
                if recipe_item.name.toLowerCase() == pantry_item.name.toLowerCase() {
                    used_qty += recipe_item.quantity;
                }
            }
            remaining_qty = pantry_item.quantity - used_qty;
            if remaining_qty > 0 {
                updated_pantry = updated_pantry.concat([{
                    "name": pantry_item.name,
                    "quantity": remaining_qty,
                    "unit": pantry_item.unit,
                    "cost": pantry_item.cost,
                    "protein": pantry_item.protein,
                    "carb": pantry_item.carb,
                    "fat": pantry_item.fat
                }]);
            }
        }
        pantry = updated_pantry;
    }

    # Persist profile to graph storage.
    async def save_user_profile -> None {
        ensure_user_id();
        if not is_int_str(user_id) {
            status = "Save failed: could not generate a valid user_id.";
            add_debug("error", "save_user_profile.validation", {"user_id": user_id, "reason": "auto-generation failed"});
            return;
        }
        if not is_int_str(age) {
            status = "Save failed: age must be an integer.";
            add_debug("error", "save_user_profile.validation", {"age": age, "reason": "not integer"});
            return;
        }
        if not is_num_str(height) {
            status = "Save failed: height must be a number (inches).";
            add_debug("error", "save_user_profile.validation", {"height": height, "reason": "not number"});
            return;
        }
        if not is_num_str(weight) {
            status = "Save failed: weight must be a number (pounds).";
            add_debug("error", "save_user_profile.validation", {"weight": weight, "reason": "not number"});
            return;
        }

        loading = true;
        status = "Saving user profile...";
        try {
            profile_payload = build_profile();
            add_debug("request", "SaveUserProfile", {"profile": profile_payload});
            result = root spawn SaveUserProfile(profile=profile_payload);
            add_debug("response", "SaveUserProfile", {"raw_result": result});

            save_out = result.reports[0];
            if save_out.saved {
                user_profile = profile_payload;
                status = "User profile saved.";
            } else {
                status = "Save failed: " + JSON.stringify(save_out, None, 2);
                add_debug("error", "SaveUserProfile.reported_error", {"save_out": save_out});
            }
        } except Exception as e {
            err_payload = build_error_payload("SaveUserProfile.exception", e);
            add_debug("error", "SaveUserProfile.exception", err_payload);
            status = "Save failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Load current profile from backend into form + UI state.
    async def load_user_profile -> None {
        loading = true;
        status = "Loading user profile...";
        try {
            add_debug("request", "GetUserProfile", {});
            result = root spawn GetUserProfile();
            add_debug("response", "GetUserProfile", {"raw_result": result});
            data = result.reports[0];
            if Object.keys(data).length > 0 {
                user_profile = data;
                user_id = data.user_id.toString();
                age = data.age.toString();
                sex = data.sex.toUpperCase();
                height = data.height.toString();
                weight = data.weight.toString();
                dietary_restrictions_text = data.dietary_restrictions.join(", ");
                allergies_text = data.allergies.join(", ");
                fitness_level = data.fitness_level.toUpperCase();
                goal = data.goal.toUpperCase();
                status = "User profile loaded.";
            } else {
                status = "No saved user profile found.";
            }
        } except Exception as e {
            err_payload = build_error_payload("GetUserProfile.exception", e);
            add_debug("error", "GetUserProfile.exception", err_payload);
            status = "Load failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Delete stored profile.
    async def clear_user_profile -> None {
        loading = true;
        status = "Clearing user profile...";
        try {
            add_debug("request", "ClearUserProfile", {});
            root spawn ClearUserProfile();
            add_debug("response", "ClearUserProfile", {"ok": true});
            user_profile = {};
            macro_needs = {};
            status = "User profile cleared.";
        } except Exception as e {
            err_payload = build_error_payload("ClearUserProfile.exception", e);
            add_debug("error", "ClearUserProfile.exception", err_payload);
            status = "Clear failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Trigger macro calculation from stored profile.
    async def generate_macro_needs -> None {
        loading = true;
        status = "Generating macro needs...";
        try {
            add_debug("request", "GenerateUserMacroNeeds", {});
            result = root spawn GenerateUserMacroNeeds();
            add_debug("response", "GenerateUserMacroNeeds", {"raw_result": result});
            macro_out = result.reports[0];
            if macro_out.ok {
                macro_needs = macro_out;
                status = "Macro needs generated.";
            } else {
                macro_needs = {};
                status = "Macro generation failed: " + macro_out.error;
                add_debug("error", "GenerateUserMacroNeeds.reported_error", {"macro_out": macro_out});
            }
        } except Exception as e {
            err_payload = build_error_payload("GenerateUserMacroNeeds.exception", e);
            add_debug("error", "GenerateUserMacroNeeds.exception", err_payload);
            status = "Macro generation failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Generate recipe from profile + pantry, then update local pantry quantities.
    async def generate_recipe -> None {
        if pantry.length == 0 {
            status = "Add pantry ingredients first.";
            return;
        }

        profile_obj = build_profile();
        if Object.keys(user_profile).length > 0 {
            profile_obj = {
                "user_id": user_profile.user_id,
                "age": user_profile.age,
                "sex": user_profile.sex.toUpperCase(),
                "height": user_profile.height,
                "weight": user_profile.weight,
                "dietary_restrictions": user_profile.dietary_restrictions,
                "allergies": user_profile.allergies,
                "fitness_level": user_profile.fitness_level.toUpperCase(),
                "goal": user_profile.goal.toUpperCase()
            };
        }
        loading = true;
        status = "Generating recipe from pantry...";
        try {
            add_debug("request", "GenerateRecipeFromPantry", {"profile": profile_obj, "pantry_ingredients": pantry});
            result = root spawn GenerateRecipeFromPantry(
                profile=profile_obj,
                pantry_ingredients=pantry
            );
            add_debug("response", "GenerateRecipeFromPantry", {"raw_result": result});
            generated = result.reports[0];
            recipe = generated;
            if generated.ingredients {
                subtract_recipe_from_pantry(generated.ingredients);
            }
            status = "Recipe generated and pantry updated.";
        } except Exception as e {
            err_payload = build_error_payload("GenerateRecipeFromPantry.exception", e);
            add_debug("error", "GenerateRecipeFromPantry.exception", err_payload);
            status = "Recipe generation failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Read latest stored generated recipe.
    async def reload_saved_recipe -> None {
        loading = true;
        status = "Loading saved recipe...";
        try {
            add_debug("request", "ListGeneratedRecipe", {});
            result = root spawn ListGeneratedRecipe();
            add_debug("response", "ListGeneratedRecipe", {"raw_result": result});
            recipe = result.reports[0];
            status = "Saved recipe loaded.";
        } except Exception as e {
            err_payload = build_error_payload("ListGeneratedRecipe.exception", e);
            add_debug("error", "ListGeneratedRecipe.exception", err_payload);
            status = "Load recipe failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Remove stored generated recipe state.
    async def clear_recipe -> None {
        loading = true;
        status = "Clearing generated recipe...";
        try {
            add_debug("request", "ClearGeneratedRecipe", {});
            root spawn ClearGeneratedRecipe();
            add_debug("response", "ClearGeneratedRecipe", {"ok": true});
            recipe = {};
            status = "Generated recipe cleared.";
        } except Exception as e {
            err_payload = build_error_payload("ClearGeneratedRecipe.exception", e);
            add_debug("error", "ClearGeneratedRecipe.exception", err_payload);
            status = "Clear recipe failed: " + err_payload.error_text;
        }
        loading = false;
    }

    # Reset survey form values without touching saved backend data.
    def clear_survey_form() -> None {
        ensure_user_id();
        survey_name = "";
        survey_age = "";
        survey_sex = "MALE";
        survey_height = "";
        survey_weight = "";
        survey_goal = "MUSCLE_GAIN";
        survey_fitness_level = "MODERATELY_ACTIVE";
        survey_cooking_days = "4";
        survey_meals_per_day = "3";
        survey_budget = "medium";
        survey_time_minutes = "30";
        survey_skill = "intermediate";
        survey_dietary_notes = "";
        survey_allergy_notes = "";
        survey_dislikes = "";
        survey_response = {};
        survey_step = 0;
        status = "Survey form cleared.";
    }

    def next_survey_step() -> None {
        if survey_step < 3 {
            if can_advance_survey() {
                survey_step = survey_step + 1;
            } else {
                status = "Please fill required fields before moving to the next step.";
            }
        }
    }

    def prev_survey_step() -> None {
        if survey_step > 0 {
            survey_step = survey_step - 1;
        }
    }

    def set_survey_step(step: int) -> None {
        if step >= 0 and step <= 3 {
            survey_step = step;
        }
    }

    def survey_answered_field_count() -> int {
        count = 0;
        if survey_age.trim().length > 0 { count += 1; }
        if survey_sex.trim().length > 0 { count += 1; }
        if survey_height.trim().length > 0 { count += 1; }
        if survey_weight.trim().length > 0 { count += 1; }
        if survey_goal.trim().length > 0 { count += 1; }
        if survey_fitness_level.trim().length > 0 { count += 1; }
        if survey_cooking_days.trim().length > 0 { count += 1; }
        if survey_meals_per_day.trim().length > 0 { count += 1; }
        if survey_budget.trim().length > 0 { count += 1; }
        if survey_time_minutes.trim().length > 0 { count += 1; }
        if survey_skill.trim().length > 0 { count += 1; }
        if survey_dietary_notes.trim().length > 0 { count += 1; }
        if survey_allergy_notes.trim().length > 0 { count += 1; }
        if survey_dislikes.trim().length > 0 { count += 1; }
        return count;
    }

    def survey_total_field_count() -> int {
        return 14;
    }

    def survey_progress_percent() -> int {
        return parseInt(((survey_answered_field_count() * 100) / survey_total_field_count()).toString());
    }

    def survey_step_title() -> str {
        if survey_step == 0 {
            return "Basics";
        } elif survey_step == 1 {
            return "Goals";
        } elif survey_step == 2 {
            return "Lifestyle";
        }
        return "Review";
    }

    def survey_step_hint() -> str {
        if survey_step == 0 {
            return "Tell us who you are so plans can be personalized.";
        } elif survey_step == 1 {
            return "Define your nutrition direction and activity baseline.";
        } elif survey_step == 2 {
            return "Share constraints that shape realistic meals.";
        }
        return "Check your answers and submit to the console flow.";
    }

    def can_advance_survey() -> bool {
        if survey_step == 0 {
            return (
                survey_age.trim().length > 0 and
                survey_height.trim().length > 0
            );
        } elif survey_step == 1 {
            return survey_weight.trim().length > 0;
        } elif survey_step == 2 {
            return survey_time_minutes.trim().length > 0;
        }
        return true;
    }

    # Move survey answers into the existing profile form used by backend walkers.
    def apply_survey_to_profile() -> None {
        ensure_user_id();
        norm_age = normalize_int_text(survey_age);
        if norm_age {
            survey_age = norm_age;
        }
        if survey_age.trim() {
            age = survey_age.trim();
        }
        if survey_height.trim() {
            height = survey_height.trim();
        }
        if survey_weight.trim() {
            weight = survey_weight.trim();
        }
        sex = survey_sex;
        goal = survey_goal;
        fitness_level = survey_fitness_level;
        dietary_restrictions_text = survey_dietary_notes;
        allergies_text = survey_allergy_notes;

        survey_response = {
            "name": survey_name.trim(),
            "user_id": user_id,
            "age": survey_age.trim(),
            "sex": survey_sex,
            "height": survey_height.trim(),
            "weight": survey_weight.trim(),
            "goal": survey_goal,
            "fitness_level": survey_fitness_level,
            "cook_days_per_week": survey_cooking_days.trim(),
            "meals_per_day": survey_meals_per_day.trim(),
            "budget_level": survey_budget,
            "time_per_meal_minutes": survey_time_minutes.trim(),
            "kitchen_skill": survey_skill,
            "dietary_restrictions": split_csv(survey_dietary_notes),
            "allergies": split_csv(survey_allergy_notes),
            "disliked_foods": split_csv(survey_dislikes)
        };

        status = "Survey applied. You can continue in the Console tab.";
        active_tab = "console";
    }

    async def apply_survey_and_save -> None {
        apply_survey_to_profile();
        profile_payload = build_survey_profile_payload();
        if Object.keys(profile_payload).length == 0 {
            status = "Save failed: age, height, and weight must be valid numbers.";
            return;
        }

        loading = true;
        status = "Saving survey profile...";
        try {
            add_debug("request", "SaveUserProfile", {"profile": profile_payload, "source": "survey"});
            result = root spawn SaveUserProfile(profile=profile_payload);
            add_debug("response", "SaveUserProfile", {"raw_result": result, "source": "survey"});
            save_out = result.reports[0];
            if save_out.saved {
                user_profile = profile_payload;
                user_id = profile_payload.user_id.toString();
                age = profile_payload.age.toString();
                height = profile_payload.height.toString();
                weight = profile_payload.weight.toString();
                status = "Survey profile saved.";
            } else {
                status = "Save failed: " + JSON.stringify(save_out, None, 2);
            }
        } except Exception as e {
            err_payload = build_error_payload("SaveUserProfile.survey_exception", e);
            add_debug("error", "SaveUserProfile.survey_exception", err_payload);
            status = "Save failed: " + err_payload.error_text;
        }
        loading = false;
    }

    can with entry {
        ensure_user_id();
    }

    # UI sections:
    # - Status + tab switcher
    # - Survey tab
    # - Existing console tab
    return
        <div
            style={{
                "fontFamily": "'Avenir Next', 'Segoe UI', sans-serif",
                "background": ("linear-gradient(140deg, #dbeafe 0%, #bfdbfe 55%, #93c5fd 100%)" if active_tab == "survey" else "linear-gradient(140deg, #f6f8fc 0%, #e8fff7 55%, #fff3de 100%)"),
                "minHeight": "100vh",
                "padding": "20px",
                "color": "#11203a"
            }}
        >
            <div
                style={{
                    "maxWidth": "1100px",
                    "margin": "0 auto",
                    "display": "grid",
                    "gap": "16px"
                }}
            >
                <h1 style={{"margin": "0", "fontSize": "2rem"}}>
                    CaloReceipt
                </h1>
                <div
                    style={{
                        "padding": "10px 12px",
                        "borderRadius": "10px",
                        "background": ("#e0edff" if active_tab == "survey" else "#ffffffcc"),
                        "border": ("1px solid #93c5fd" if active_tab == "survey" else "1px solid #d9e2ef"),
                        "fontWeight": "600"
                    }}
                >
                    {[( "Working..." if loading else "Ready"), " | ", status].join("")}
                </div>
                <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                    <button
                        onClick={lambda -> None { active_tab = "console"; }}
                        style={{
                            "background": ("#0f172a" if active_tab == "console" else "#ffffff"),
                            "color": ("#ffffff" if active_tab == "console" else "#0f172a"),
                            "border": "1px solid #cbd5e1",
                            "borderRadius": "10px",
                            "padding": "8px 14px",
                            "fontWeight": "700"
                        }}
                    >
                        Console
                    </button>
                    <button
                        onClick={lambda -> None { active_tab = "survey"; }}
                        style={{
                            "background": ("#0f172a" if active_tab == "survey" else "#ffffff"),
                            "color": ("#ffffff" if active_tab == "survey" else "#0f172a"),
                            "border": "1px solid #cbd5e1",
                            "borderRadius": "10px",
                            "padding": "8px 14px",
                            "fontWeight": "700"
                        }}
                    >
                        Survey
                    </button>
                </div>
                {(
                    <div
                        style={{
                            "background": "#e8f1ff",
                            "border": "1px solid #93c5fd",
                            "borderRadius": "14px",
                            "padding": "18px",
                            "display": "grid",
                            "gap": "14px"
                        }}
                    >
                        <div
                            style={{
                                "background": "linear-gradient(135deg, #0f172a 0%, #1d4ed8 50%, #0891b2 100%)",
                                "borderRadius": "14px",
                                "padding": "16px",
                                "color": "#f8fafc"
                            }}
                        >
                            <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center", "gap": "10px", "flexWrap": "wrap"}}>
                                <div>
                                    <h2 style={{"margin": "0 0 4px 0"}}>Nutrition Survey</h2>
                                    <p style={{"margin": "0", "opacity": "0.9"}}>
                                        {survey_step_hint()}
                                    </p>
                                </div>
                                <div style={{"fontWeight": "700", "background": "#ffffff22", "border": "1px solid #ffffff44", "padding": "6px 10px", "borderRadius": "999px"}}>
                                    Step {String(survey_step + 1)} of 4
                                </div>
                            </div>
                            <div style={{"marginTop": "12px"}}>
                                <div style={{"display": "flex", "justifyContent": "space-between", "fontSize": "0.9rem", "fontWeight": "700"}}>
                                    <span>Progress</span>
                                    <span>
                                        {survey_answered_field_count()} / {survey_total_field_count()} fields
                                        {" ("}{String(survey_progress_percent())}{"%)"}
                                    </span>
                                </div>
                                <div style={{"marginTop": "6px", "height": "10px", "background": "#ffffff33", "borderRadius": "999px", "overflow": "hidden"}}>
                                    <div
                                        style={{
                                            "height": "100%",
                                            "width": [String(survey_progress_percent()), "%"].join(""),
                                            "background": "linear-gradient(90deg, #60a5fa 0%, #22d3ee 100%)",
                                            "borderRadius": "999px",
                                            "transition": "width 250ms ease"
                                        }}
                                    />
                                </div>
                            </div>
                            <div style={{"display": "grid", "gridTemplateColumns": "repeat(4, minmax(0, 1fr))", "gap": "8px", "marginTop": "12px"}}>
                                <button onClick={lambda -> None { set_survey_step(0); }} style={{"textAlign": "center", "padding": "6px 8px", "borderRadius": "8px", "background": ("#ffffff38" if survey_step >= 0 else "#ffffff14"), "border": "1px solid #ffffff33", "color": "#ffffff"}}>Basics</button>
                                <button onClick={lambda -> None { set_survey_step(1); }} style={{"textAlign": "center", "padding": "6px 8px", "borderRadius": "8px", "background": ("#ffffff38" if survey_step >= 1 else "#ffffff14"), "border": "1px solid #ffffff33", "color": "#ffffff"}}>Goals</button>
                                <button onClick={lambda -> None { set_survey_step(2); }} style={{"textAlign": "center", "padding": "6px 8px", "borderRadius": "8px", "background": ("#ffffff38" if survey_step >= 2 else "#ffffff14"), "border": "1px solid #ffffff33", "color": "#ffffff"}}>Lifestyle</button>
                                <button onClick={lambda -> None { set_survey_step(3); }} style={{"textAlign": "center", "padding": "6px 8px", "borderRadius": "8px", "background": ("#ffffff38" if survey_step >= 3 else "#ffffff14"), "border": "1px solid #ffffff33", "color": "#ffffff"}}>Review</button>
                            </div>
                        </div>

                        <div style={{"display": "grid", "gridTemplateColumns": "minmax(0, 2fr) minmax(260px, 1fr)", "gap": "14px"}}>
                            <div style={{"background": "#ffffff", "border": "1px solid #dbe4f0", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px"}}>
                                <div>
                                    <h3 style={{"margin": "0"}}>{survey_step_title()}</h3>
                                    <p style={{"margin": "4px 0 0 0", "opacity": "0.75"}}>
                                        {survey_step_hint()}
                                    </p>
                                </div>
                                {(
                                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(220px, 1fr))", "gap": "10px"}}>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Name</div>
                                            <input value={survey_name} onChange={lambda e: any -> None { survey_name = e.target.value; }} placeholder="Name (optional)" />
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>User ID (auto)</div>
                                            <div style={{"background": "#ffffff", "border": "1px dashed #93c5fd", "borderRadius": "8px", "padding": "8px 10px", "fontFamily": "monospace"}}>
                                                {user_id}
                                            </div>
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Age *</div>
                                            <input value={survey_age} onChange={lambda e: any -> None { survey_age = e.target.value; }} placeholder="Age" />
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Sex</div>
                                            <select value={survey_sex} onChange={lambda e: any -> None { survey_sex = e.target.value; }}>
                                                <option value="MALE">MALE</option>
                                                <option value="FEMALE">FEMALE</option>
                                                <option value="OTHER">OTHER</option>
                                                <option value="PREFER_NOT_TO_SAY">PREFER_NOT_TO_SAY</option>
                                            </select>
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Height (inches) *</div>
                                            <input value={survey_height} onChange={lambda e: any -> None { survey_height = e.target.value; }} placeholder="Height (inches)" />
                                        </div>
                                    </div>
                                ) if survey_step == 0 else <div /> }
                                {(
                                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(220px, 1fr))", "gap": "10px"}}>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Weight (pounds) *</div>
                                            <input value={survey_weight} onChange={lambda e: any -> None { survey_weight = e.target.value; }} placeholder="Weight (pounds)" />
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Goal</div>
                                            <select value={survey_goal} onChange={lambda e: any -> None { survey_goal = e.target.value; }}>
                                                <option value="FAT_LOSS">FAT_LOSS</option>
                                                <option value="MAINTENANCE">MAINTENANCE</option>
                                                <option value="LEAN_BULK">LEAN_BULK</option>
                                                <option value="MUSCLE_GAIN">MUSCLE_GAIN</option>
                                                <option value="ENDURANCE_PERFORMANCE">ENDURANCE_PERFORMANCE</option>
                                            </select>
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Fitness Level</div>
                                            <select value={survey_fitness_level} onChange={lambda e: any -> None { survey_fitness_level = e.target.value; }}>
                                                <option value="SEDENTARY">SEDENTARY</option>
                                                <option value="LIGHTLY_ACTIVE">LIGHTLY_ACTIVE</option>
                                                <option value="MODERATELY_ACTIVE">MODERATELY_ACTIVE</option>
                                                <option value="VERY_ACTIVE">VERY_ACTIVE</option>
                                                <option value="ATHLETE">ATHLETE</option>
                                            </select>
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Cook Days / Week</div>
                                            <input value={survey_cooking_days} onChange={lambda e: any -> None { survey_cooking_days = e.target.value; }} placeholder="Cook days per week" />
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Meals / Day</div>
                                            <input value={survey_meals_per_day} onChange={lambda e: any -> None { survey_meals_per_day = e.target.value; }} placeholder="Meals per day" />
                                        </div>
                                    </div>
                                ) if survey_step == 1 else <div /> }
                                {(
                                    <div style={{"display": "grid", "gridTemplateColumns": "repeat(auto-fit, minmax(220px, 1fr))", "gap": "10px"}}>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Minutes Per Meal *</div>
                                            <input value={survey_time_minutes} onChange={lambda e: any -> None { survey_time_minutes = e.target.value; }} placeholder="Minutes available per meal" />
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Budget</div>
                                            <select value={survey_budget} onChange={lambda e: any -> None { survey_budget = e.target.value; }}>
                                                <option value="low">low budget</option>
                                                <option value="medium">medium budget</option>
                                                <option value="high">high budget</option>
                                            </select>
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Kitchen Skill</div>
                                            <select value={survey_skill} onChange={lambda e: any -> None { survey_skill = e.target.value; }}>
                                                <option value="beginner">beginner cook</option>
                                                <option value="intermediate">intermediate cook</option>
                                                <option value="advanced">advanced cook</option>
                                            </select>
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Dietary Restrictions</div>
                                            <input value={survey_dietary_notes} onChange={lambda e: any -> None { survey_dietary_notes = e.target.value; }} placeholder="Dietary restrictions (comma separated)" />
                                        </div>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Allergies</div>
                                            <input value={survey_allergy_notes} onChange={lambda e: any -> None { survey_allergy_notes = e.target.value; }} placeholder="Allergies (comma separated)" />
                                        </div>
                                    </div>
                                ) if survey_step == 2 else <div /> }
                                {(
                                    <div style={{"display": "grid", "gap": "10px"}}>
                                        <div style={{"background": "#f8fafc", "border": "1px solid #e2e8f0", "borderRadius": "10px", "padding": "10px"}}>
                                            <div style={{"fontWeight": "700", "marginBottom": "6px"}}>Disliked Foods</div>
                                            <input value={survey_dislikes} onChange={lambda e: any -> None { survey_dislikes = e.target.value; }} placeholder="Foods you dislike (comma separated)" />
                                        </div>
                                        <p style={{"margin": "0", "opacity": "0.8"}}>
                                            Ready to submit your survey answers to the console workflow.
                                        </p>
                                    </div>
                                ) if survey_step == 3 else <div /> }
                            </div>

                            <div style={{"background": "#eaf2ff", "border": "1px solid #bfdbfe", "borderRadius": "14px", "padding": "14px", "display": "grid", "gap": "10px", "height": "fit-content"}}>
                                <h3 style={{"margin": "0"}}>Live Summary</h3>
                                <div style={{"fontSize": "0.9rem"}}>
                                    <div><b>User:</b> {survey_name if survey_name.trim() else "Not provided"}</div>
                                    <div><b>ID:</b> {user_id if user_id.trim() else "-"}</div>
                                    <div><b>Age/Sex:</b> {(survey_age if survey_age.trim() else "-")} / {survey_sex}</div>
                                    <div><b>Height/Weight:</b> {(survey_height if survey_height.trim() else "-")} in / {(survey_weight if survey_weight.trim() else "-")} lb</div>
                                    <div><b>Goal:</b> {survey_goal}</div>
                                    <div><b>Fitness:</b> {survey_fitness_level}</div>
                                    <div><b>Meals/Day:</b> {survey_meals_per_day}</div>
                                    <div><b>Time/Meal:</b> {survey_time_minutes} min</div>
                                    <div><b>Budget:</b> {survey_budget}</div>
                                </div>
                                <div style={{"fontSize": "0.85rem", "opacity": "0.8", "background": "#f8fbff", "border": "1px dashed #93c5fd", "borderRadius": "10px", "padding": "8px"}}>
                                    Required now:
                                    {(
                                        <span> Age, Height</span>
                                    ) if survey_step == 0 else (
                                        <span> Weight</span>
                                    ) if survey_step == 1 else (
                                        <span> Minutes Per Meal</span>
                                    ) if survey_step == 2 else (
                                        <span> Final review only</span>
                                    )}
                                </div>
                            </div>
                        </div>

                        {(
                            <div style={{"padding": "10px 12px", "borderRadius": "10px", "border": "1px solid #fca5a5", "background": "#fff1f2", "color": "#9f1239", "fontWeight": "600"}}>
                                Some required fields are missing for this step.
                            </div>
                        ) if (survey_step < 3 and not can_advance_survey()) else <div /> }

                        <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                            <button
                                onClick={prev_survey_step}
                                disabled={survey_step == 0}
                                style={{"padding": "8px 14px", "borderRadius": "10px", "border": "1px solid #cbd5e1", "background": ("#f1f5f9" if survey_step == 0 else "#ffffff")}}
                            >
                                Back
                            </button>
                            <button
                                onClick={next_survey_step}
                                disabled={survey_step == 3 or not can_advance_survey()}
                                style={{"padding": "8px 14px", "borderRadius": "10px", "border": "1px solid #1d4ed8", "background": ("#dbeafe" if (survey_step == 3 or not can_advance_survey()) else "#2563eb"), "color": ("#1e3a8a" if (survey_step == 3 or not can_advance_survey()) else "#ffffff"), "fontWeight": "700"}}
                            >
                                Next
                            </button>
                            <button onClick={clear_survey_form} style={{"padding": "8px 14px", "borderRadius": "10px", "border": "1px solid #cbd5e1"}}>
                                Clear Survey
                            </button>
                            {(
                                <button onClick={apply_survey_to_profile} style={{"padding": "8px 14px", "borderRadius": "10px", "border": "1px solid #0f766e", "background": "#14b8a6", "color": "#ffffff", "fontWeight": "700"}}>
                                    Apply Survey To Console
                                </button>
                            ) if survey_step == 3 else <div /> }
                            {(
                                <button onClick={apply_survey_and_save} style={{"padding": "8px 14px", "borderRadius": "10px", "border": "1px solid #166534", "background": "#22c55e", "color": "#052e16", "fontWeight": "700"}}>
                                    Apply + Save Profile
                                </button>
                            ) if survey_step == 3 else <div /> }
                        </div>
                        <div>
                            <h3 style={{"marginBottom": "8px"}}>Latest Applied Survey Payload</h3>
                            <pre style={{"background": "#0f172a", "color": "#bae6fd", "padding": "10px", "borderRadius": "8px", "overflowX": "auto"}}>
                                {JSON.stringify(survey_response, None, 2)}
                            </pre>
                        </div>
                    </div>
                ) if active_tab == "survey" else (
                    <div style={{"display": "grid", "gap": "16px"}}>
                        <div
                            style={{
                                "background": "#fff7ed",
                                "border": "1px solid #fdba74",
                                "borderRadius": "14px",
                                "padding": "16px"
                            }}
                        >
                            <div style={{"display": "flex", "gap": "8px", "alignItems": "center", "flexWrap": "wrap"}}>
                                <h2 style={{"margin": "0"}}>Debug Console</h2>
                                <button onClick={lambda -> None { show_debug = not show_debug; }}>
                                    {( "Hide Debug" if show_debug else "Show Debug" )}
                                </button>
                                <button onClick={lambda -> None { debug_events = []; last_error = {}; }}>
                                    Clear Debug Logs
                                </button>
                            </div>
                            {(
                                <div style={{"marginTop": "10px"}}>
                                    <h3>Last Error</h3>
                                    <pre style={{"background": "#111827", "color": "#fecaca", "padding": "10px", "borderRadius": "8px", "overflowX": "auto"}}>
                                        {JSON.stringify(last_error, None, 2)}
                                    </pre>
                                    <h3>Debug Events (latest 50)</h3>
                                    <pre style={{"background": "#111827", "color": "#bfdbfe", "padding": "10px", "borderRadius": "8px", "overflowX": "auto"}}>
                                        {JSON.stringify(debug_events, None, 2)}
                                    </pre>
                                </div>
                            ) if show_debug else <div /> }
                        </div>
                        <div
                            style={{
                                "background": "#ffffffd9",
                                "border": "1px solid #d9e2ef",
                                "borderRadius": "14px",
                                "padding": "16px"
                            }}
                        >
                            <h2>User Profile</h2>
                            <div style={{"marginBottom": "10px", "fontWeight": "700"}}>
                                User ID (auto-generated): <span style={{"fontFamily": "monospace"}}>{user_id}</span>
                            </div>
                            <div style={{"display": "grid", "gridTemplateColumns": "repeat(4, minmax(0, 1fr))", "gap": "8px"}}>
                                <input value={age} onChange={lambda e: any -> None { age = e.target.value; }} placeholder="Age" />
                                <input value={height} onChange={lambda e: any -> None { height = e.target.value; }} placeholder="Height (in)" />
                                <input value={weight} onChange={lambda e: any -> None { weight = e.target.value; }} placeholder="Weight (lb)" />
                                <select value={sex} onChange={lambda e: any -> None { sex = e.target.value; }}>
                                    <option value="MALE">MALE</option>
                                    <option value="FEMALE">FEMALE</option>
                                    <option value="OTHER">OTHER</option>
                                    <option value="PREFER_NOT_TO_SAY">PREFER_NOT_TO_SAY</option>
                                </select>
                                <select value={fitness_level} onChange={lambda e: any -> None { fitness_level = e.target.value; }}>
                                    <option value="SEDENTARY">SEDENTARY</option>
                                    <option value="LIGHTLY_ACTIVE">LIGHTLY_ACTIVE</option>
                                    <option value="MODERATELY_ACTIVE">MODERATELY_ACTIVE</option>
                                    <option value="VERY_ACTIVE">VERY_ACTIVE</option>
                                    <option value="ATHLETE">ATHLETE</option>
                                </select>
                                <select value={goal} onChange={lambda e: any -> None { goal = e.target.value; }}>
                                    <option value="FAT_LOSS">FAT_LOSS</option>
                                    <option value="MAINTENANCE">MAINTENANCE</option>
                                    <option value="LEAN_BULK">LEAN_BULK</option>
                                    <option value="MUSCLE_GAIN">MUSCLE_GAIN</option>
                                    <option value="ENDURANCE_PERFORMANCE">ENDURANCE_PERFORMANCE</option>
                                </select>
                                <input value={dietary_restrictions_text} onChange={lambda e: any -> None { dietary_restrictions_text = e.target.value; }} placeholder="dietary restrictions (comma separated)" />
                                <input value={allergies_text} onChange={lambda e: any -> None { allergies_text = e.target.value; }} placeholder="allergies (comma separated)" />
                            </div>
                            <div style={{"display": "flex", "gap": "8px", "marginTop": "12px", "flexWrap": "wrap"}}>
                                <button onClick={save_user_profile}>Save User</button>
                                <button onClick={load_user_profile}>Load User</button>
                                <button onClick={clear_user_profile}>Clear User</button>
                                <button onClick={generate_macro_needs}>Generate Macros</button>
                            </div>
                            <h3>Saved User</h3>
                            <pre style={{"background": "#0f172a", "color": "#d1fae5", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                                {JSON.stringify(user_profile, None, 2)}
                            </pre>
                            <h3>Macro Needs</h3>
                            <pre style={{"background": "#0f172a", "color": "#d1fae5", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                                {JSON.stringify(macro_needs, None, 2)}
                            </pre>
                        </div>
                        <div
                            style={{
                                "background": "#ffffffd9",
                                "border": "1px solid #d9e2ef",
                                "borderRadius": "14px",
                                "padding": "16px"
                            }}
                        >
                            <h2>Receipt OCR Import</h2>
                            <div style={{"display": "flex", "gap": "10px", "alignItems": "center", "flexWrap": "wrap"}}>
                                <input type="file" accept="image/*" onChange={on_receipt_image_change} />
                                <button onClick={import_receipt_to_pantry}>OCR Import To Pantry</button>
                                <span>{receipt_image_name}</span>
                            </div>
                            <h3>OCR Text</h3>
                            <pre style={{"background": "#0f172a", "color": "#bfdbfe", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto", "maxHeight": "180px", "overflowY": "auto"}}>
                                {receipt_ocr_text}
                            </pre>
                            <h3>Parsed Receipt Items</h3>
                            <pre style={{"background": "#0f172a", "color": "#fde68a", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                                {JSON.stringify(receipt_parse, None, 2)}
                            </pre>
                        </div>
                        <div
                            style={{
                                "background": "#ffffffd9",
                                "border": "1px solid #d9e2ef",
                                "borderRadius": "14px",
                                "padding": "16px"
                            }}
                        >
                            <h2>Pantry</h2>
                            <div style={{"display": "grid", "gridTemplateColumns": "2fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr", "gap": "8px"}}>
                                <input value={ing_name} onChange={lambda e: any -> None { ing_name = e.target.value; }} placeholder="name" />
                                <input value={ing_quantity} onChange={lambda e: any -> None { ing_quantity = e.target.value; }} placeholder="qty" />
                                <select value={ing_unit} onChange={lambda e: any -> None { ing_unit = e.target.value; }}>
                                    <option value="PIECE">PIECE</option>
                                    <option value="LB">LB</option>
                                    <option value="OZ">OZ</option>
                                    <option value="CUP">CUP</option>
                                    <option value="TBSP">TBSP</option>
                                    <option value="TSP">TSP</option>
                                    <option value="CLOVE">CLOVE</option>
                                    <option value="BUNCH">BUNCH</option>
                                </select>
                                <input value={ing_cost} onChange={lambda e: any -> None { ing_cost = e.target.value; }} placeholder="cost" />
                                <input value={ing_protein} onChange={lambda e: any -> None { ing_protein = e.target.value; }} placeholder="protein" />
                                <input value={ing_carb} onChange={lambda e: any -> None { ing_carb = e.target.value; }} placeholder="carb" />
                                <input value={ing_fat} onChange={lambda e: any -> None { ing_fat = e.target.value; }} placeholder="fat" />
                                <button onClick={add_pantry_item}>Add</button>
                            </div>
                            <div style={{"marginTop": "12px"}}>
                                {(
                                    <div>No pantry items yet.</div>
                                )
                                if pantry.length == 0
                                else (
                                    <table style={{"width": "100%", "borderCollapse": "collapse"}}>
                                        <thead>
                                            <tr>
                                                <th>Name</th><th>Qty</th><th>Unit</th><th>Cost</th><th>P</th><th>C</th><th>F</th><th>Actions</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {pantry.map(
                                                lambda item: dict -> JsxElement { return
                                                    <tr key={item.name}>
                                                        <td>{item.name}</td>
                                                        <td>{item.quantity}</td>
                                                        <td>{item.unit}</td>
                                                        <td>{item.cost}</td>
                                                        <td>{item.protein}</td>
                                                        <td>{item.carb}</td>
                                                        <td>{item.fat}</td>
                                                        <td><button onClick={lambda -> None { remove_pantry_item(item.name); }}>Remove</button></td>
                                                    </tr>; }
                                            )}
                                        </tbody>
                                    </table>
                                )}
                            </div>
                        </div>
                        <div
                            style={{
                                "background": "#ffffffd9",
                                "border": "1px solid #d9e2ef",
                                "borderRadius": "14px",
                                "padding": "16px"
                            }}
                        >
                            <h2>Recipe</h2>
                            <div style={{"display": "flex", "gap": "8px", "flexWrap": "wrap"}}>
                                <button onClick={generate_recipe}>Generate Recipe From Pantry</button>
                                <button onClick={reload_saved_recipe}>Load Saved Recipe</button>
                                <button onClick={clear_recipe}>Clear Recipe</button>
                            </div>
                            <pre style={{"background": "#0f172a", "color": "#fef3c7", "padding": "10px", "borderRadius": "8px", "marginTop": "10px", "overflowX": "auto"}}>
                                {JSON.stringify(recipe, None, 2)}
                            </pre>
                            {(
                                <ol>
                                    {recipe.instructions.map(
                                        lambda step: str -> JsxElement { return <li key={step}>{step}</li>; }
                                    )}
                                </ol>
                            )
                            if (recipe and recipe.instructions and recipe.instructions.length > 0)
                            else <div /> }
                        </div>
                    </div>
                )}
            </div>
        </div>;
}
