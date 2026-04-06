import from llm_config {
    llm
}
import datetime;

# Core profile dimensions used by nutrition planning.
enum Sex { MALE, FEMALE, OTHER, PREFER_NOT_TO_SAY }

enum FitnessLevel { SEDENTARY, LIGHTLY_ACTIVE, MODERATELY_ACTIVE, VERY_ACTIVE, ATHLETE }

enum Goal {
    FAT_LOSS,
    MAINTENANCE,
    LEAN_BULK,
    MUSCLE_GAIN,
    ENDURANCE_PERFORMANCE
}

obj user {
    has age: int;
    has sex: Sex;
    has height: float;
    has weight: float;
    has fitness_level: FitnessLevel;
    has goal: Goal;
    has goal_weight: float = 0.0;
    has username: str = "";
    has dietary_restrictions: list[str] = [];
    has allergies: list[str] = [];
}

# Normalize frontend/profile payloads (string enums + numeric-like values)
# into the strongly typed `user` object expected by LLM functions/walkers.
def:pub user_from_dict(profile: dict) -> user {
    sex_in = str(profile["sex"]).upper();
    fitness_in = str(profile["fitness_level"]).upper();
    goal_in = str(profile["goal"]).upper();
    username_text = str(profile.get("username", "")).strip();

    sex_val = Sex.MALE;
    if sex_in == "FEMALE" {
        sex_val = Sex.FEMALE;
    } elif sex_in == "OTHER" {
        sex_val = Sex.OTHER;
    } elif sex_in == "PREFER_NOT_TO_SAY" {
        sex_val = Sex.PREFER_NOT_TO_SAY;
    }

    fitness_val = FitnessLevel.MODERATELY_ACTIVE;
    if fitness_in == "SEDENTARY" {
        fitness_val = FitnessLevel.SEDENTARY;
    } elif fitness_in == "LIGHTLY_ACTIVE" {
        fitness_val = FitnessLevel.LIGHTLY_ACTIVE;
    } elif fitness_in == "VERY_ACTIVE" {
        fitness_val = FitnessLevel.VERY_ACTIVE;
    } elif fitness_in == "ATHLETE" {
        fitness_val = FitnessLevel.ATHLETE;
    }

    goal_val = Goal.MUSCLE_GAIN;
    if goal_in == "FAT_LOSS" {
        goal_val = Goal.FAT_LOSS;
    } elif goal_in == "MAINTENANCE" {
        goal_val = Goal.MAINTENANCE;
    } elif goal_in == "LEAN_BULK" {
        goal_val = Goal.LEAN_BULK;
    } elif goal_in == "ENDURANCE_PERFORMANCE" {
        goal_val = Goal.ENDURANCE_PERFORMANCE;
    }

    return user(
        age=int(profile["age"]),
        sex=sex_val,
        height=float(profile["height"]),
        weight=float(profile["weight"]),
        goal_weight=float(profile.get("goal_weight", 0.0)),
        username=username_text,
        dietary_restrictions=profile["dietary_restrictions"],
        allergies=profile["allergies"],
        fitness_level=fitness_val,
        goal=goal_val
    );
}

def _profile_choice_text(raw: any) -> str {
    try {
        return str(raw).strip().upper();
    } except Exception as _e {
        return "";
    }
}

def _profile_text(raw: any) -> str {
    try {
        return str(raw).strip();
    } except Exception as _e {
        return "";
    }
}

def _profile_numeric_score(raw: any) -> int {
    try {
        if float(raw) > 0.0 {
            return 1;
        }
    } except Exception as _e {
        return 0;
    }
    return 0;
}

def _profile_payload_score(profile: dict) -> int {
    score = 0;
    score += _profile_numeric_score(profile.get("age", 0)) * 3;
    score += _profile_numeric_score(profile.get("height", 0.0)) * 3;
    score += _profile_numeric_score(profile.get("weight", 0.0)) * 3;

    sex_val = _profile_choice_text(profile.get("sex", ""));
    if sex_val == "MALE" or sex_val == "FEMALE" or sex_val == "OTHER" or sex_val == "PREFER_NOT_TO_SAY" {
        score += 2;
    }

    fitness_val = _profile_choice_text(profile.get("fitness_level", ""));
    if (
        fitness_val == "SEDENTARY" or
        fitness_val == "LIGHTLY_ACTIVE" or
        fitness_val == "MODERATELY_ACTIVE" or
        fitness_val == "VERY_ACTIVE" or
        fitness_val == "ATHLETE"
    ) {
        score += 2;
    }

    goal_val = _profile_choice_text(profile.get("goal", ""));
    if (
        goal_val == "FAT_LOSS" or
        goal_val == "MAINTENANCE" or
        goal_val == "LEAN_BULK" or
        goal_val == "MUSCLE_GAIN" or
        goal_val == "ENDURANCE_PERFORMANCE"
    ) {
        score += 2;
    }

    if _profile_text(profile.get("username", "")) != "" {
        score += 1;
    }
    try {
        if len(profile.get("dietary_restrictions", [])) > 0 {
            score += 1;
        }
    } except Exception as _e {
        0;
    }
    try {
        if len(profile.get("allergies", [])) > 0 {
            score += 1;
        }
    } except Exception as _e {
        0;
    }
    return score;
}

sem user.height = "User height in inches";
sem user.weight = "User weight in pounds";
sem user.goal_weight = "Desired body weight in pounds; use 0 when the user does not have a target weight";
sem user.dietary_restrictions = "Dietary preferences/restrictions such as vegan, halal, kosher, lactose intolerance, gluten-free";
sem user.allergies = "Food allergies or intolerances";
sem user.fitness_level = "Typical weekly activity/training level";
sem user.goal = "Primary nutrition goal";

obj MacroNeeds {
    has calories_per_day: float;
    has protein_g: float;
    has carbs_g: float;
    has fat_g: float;
    has notes: str;
}

sem MacroNeeds.calories_per_day = "Daily calorie target to support the user's goal";
sem MacroNeeds.protein_g = "Daily protein target in grams";
sem MacroNeeds.carbs_g = "Daily carbohydrate target in grams";
sem MacroNeeds.fat_g = "Daily fat target in grams";
sem MacroNeeds.notes = "Short explanation of assumptions used";

"""Generate daily calorie and macro targets based on profile and goal.
Respect allergies and dietary restrictions when shaping macro guidance.
"""
def generate_calorie_macro_needs(profile: user) -> MacroNeeds by llm();

def _round_macro(raw: float) -> float {
    return round(float(raw), 1);
}

def _fitness_multiplier(level: FitnessLevel) -> float {
    if level == FitnessLevel.SEDENTARY {
        return 1.2;
    }
    if level == FitnessLevel.LIGHTLY_ACTIVE {
        return 1.375;
    }
    if level == FitnessLevel.VERY_ACTIVE {
        return 1.725;
    }
    if level == FitnessLevel.ATHLETE {
        return 1.9;
    }
    return 1.55;
}

def _sex_bmr_offset(sex: Sex) -> float {
    if sex == Sex.FEMALE {
        return -161.0;
    }
    if sex == Sex.OTHER or sex == Sex.PREFER_NOT_TO_SAY {
        return -78.0;
    }
    return 5.0;
}

def _goal_calorie_adjustment(goal: Goal, tdee: float) -> float {
    if goal == Goal.FAT_LOSS {
        return -0.2 * tdee;
    }
    if goal == Goal.LEAN_BULK {
        return 0.08 * tdee;
    }
    if goal == Goal.MUSCLE_GAIN {
        return 0.12 * tdee;
    }
    if goal == Goal.ENDURANCE_PERFORMANCE {
        return 0.1 * tdee;
    }
    return 0.0;
}

def _goal_protein_lb(goal: Goal) -> float {
    if goal == Goal.ENDURANCE_PERFORMANCE {
        return 0.8;
    }
    if goal == Goal.MAINTENANCE {
        return 0.9;
    }
    if goal == Goal.LEAN_BULK {
        return 0.95;
    }
    return 1.0;
}

def _goal_fat_ratio(goal: Goal) -> float {
    if goal == Goal.MUSCLE_GAIN {
        return 0.25;
    }
    if goal == Goal.LEAN_BULK {
        return 0.28;
    }
    return 0.3;
}

def _macro_targets_valid(calories: float, protein: float, carbs: float, fat: float) -> bool {
    return calories > 0.0 and protein > 0.0 and carbs > 0.0 and fat > 0.0;
}

def _deterministic_macro_needs(profile: user, prior_error: str = "") -> dict {
    weight_lb = float(profile.weight);
    height_in = float(profile.height);
    age = int(profile.age);

    weight_kg = weight_lb * 0.45359237;
    height_cm = height_in * 2.54;
    bmr = (10.0 * weight_kg) + (6.25 * height_cm) - (5.0 * float(age)) + _sex_bmr_offset(profile.sex);
    activity_multiplier = _fitness_multiplier(profile.fitness_level);
    tdee = bmr * activity_multiplier;
    calories = tdee + _goal_calorie_adjustment(profile.goal, tdee);

    if calories < 1200.0 {
        calories = 1200.0;
    }

    protein_g = weight_lb * _goal_protein_lb(profile.goal);
    fat_g = (calories * _goal_fat_ratio(profile.goal)) / 9.0;
    carbs_g = (calories - (protein_g * 4.0) - (fat_g * 9.0)) / 4.0;
    if carbs_g < 50.0 {
        carbs_g = 50.0;
        fat_g = (calories - (protein_g * 4.0) - (carbs_g * 4.0)) / 9.0;
    }
    if fat_g < 25.0 {
        fat_g = 25.0;
        carbs_g = (calories - (protein_g * 4.0) - (fat_g * 9.0)) / 4.0;
    }

    calories = _round_macro(calories);
    protein_g = _round_macro(protein_g);
    carbs_g = _round_macro(carbs_g);
    fat_g = _round_macro(fat_g);

    note = (
        "Targets calculated from your saved profile with a deterministic fallback. "
        "BMR uses Mifflin-St Jeor and TDEE uses your activity level."
    );
    if str(prior_error).strip() != "" {
        note = "{} LLM guidance was unavailable: {}.".format(note, str(prior_error).strip());
    }

    return {
        "ok": True,
        "calories_per_day": calories,
        "protein_g": protein_g,
        "carbs_g": carbs_g,
        "fat_g": fat_g,
        "notes": note
    };
}


# --- Data Node ---
node UserProfile {
    has age: int,
        sex: Sex,
        height: float,
        weight: float,
        dietary_restrictions: list[str],
        allergies: list[str],
        fitness_level: FitnessLevel,
        goal: Goal,
        goal_weight: float = 0.0,
        username: str = "";
}


# --- User Walkers ---
# Upsert a single persistent user profile node in graph storage.
walker SaveUserProfile {
    has profile: dict;
    has profile_nodes: list = [];

    can save with Root entry {
        try {
            visit [-->];
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }

    can collect_existing with UserProfile entry {
        self.profile_nodes.append(here);
    }

    can finish with Root exit {
        try {
            profile_obj = user_from_dict(self.profile);
            if len(self.profile_nodes) > 0 {
                primary = self.profile_nodes[0];
                primary.age = profile_obj.age;
                primary.sex = profile_obj.sex;
                primary.height = profile_obj.height;
                primary.weight = profile_obj.weight;
                primary.dietary_restrictions = profile_obj.dietary_restrictions;
                primary.allergies = profile_obj.allergies;
                primary.fitness_level = profile_obj.fitness_level;
                primary.goal = profile_obj.goal;
                primary.goal_weight = profile_obj.goal_weight;
                primary.username = profile_obj.username;

                idx = 0;
                for profile_node in self.profile_nodes {
                    if idx > 0 {
                        del profile_node;
                    }
                    idx += 1;
                }
                save(primary);
            } else {
                new_nodes = here ++> UserProfile(
                    age=profile_obj.age,
                    sex=profile_obj.sex,
                    height=profile_obj.height,
                    weight=profile_obj.weight,
                    dietary_restrictions=profile_obj.dietary_restrictions,
                    allergies=profile_obj.allergies,
                    fitness_level=profile_obj.fitness_level,
                    goal=profile_obj.goal,
                    goal_weight=profile_obj.goal_weight,
                    username=profile_obj.username
                );
                save(new_nodes[0]);
            }
            commit();
            report {"saved": True};
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }
}

# Load the current persisted profile for frontend display/editing.
walker GetUserProfile {
    has profile: dict = {};
    has best_score: int = -1;

    can collect with Root entry {
        visit [-->];
    }

    can read with UserProfile entry {
        candidate = {
            "age": here.age,
            "sex": str(here.sex).split(".")[-1].lower(),
            "height": here.height,
            "weight": here.weight,
            "goal_weight": here.goal_weight,
            "username": here.username,
            "dietary_restrictions": here.dietary_restrictions,
            "allergies": here.allergies,
            "fitness_level": str(here.fitness_level).split(".")[-1].lower(),
            "goal": str(here.goal).split(".")[-1].lower()
        };
        candidate_score = _profile_payload_score(candidate);
        if candidate_score > self.best_score {
            self.best_score = candidate_score;
            self.profile = candidate;
        }
    }

    can report_profile with Root exit {
        report self.profile;
    }
}

# Remove profile state from the graph.
walker ClearUserProfile {
    can collect with Root entry {
        visit [-->];
    }

    can clear with UserProfile entry {
        del here;
    }

    can done with Root exit {
        report {"cleared": True};
    }
}

# Read the persisted profile, call LLM once, and return macro targets.
walker GenerateUserMacroNeeds {
    has result: dict = {};
    has did_generate: bool = False;

    can run with Root entry {
        visit [-->];
    }

    can generate with UserProfile entry {
        # Hard guard: one LLM call per request even if multiple nodes exist unexpectedly.
        if self.did_generate {
            return;
        }
        self.did_generate = True;
        profile_obj = user(
            age=here.age,
            sex=here.sex,
            height=here.height,
            weight=here.weight,
            goal_weight=here.goal_weight,
            username=here.username,
            dietary_restrictions=here.dietary_restrictions,
            allergies=here.allergies,
            fitness_level=here.fitness_level,
            goal=here.goal
        );
        llm_error = "";
        try {
            needs = generate_calorie_macro_needs(profile_obj);
            if _macro_targets_valid(
                float(needs.calories_per_day),
                float(needs.protein_g),
                float(needs.carbs_g),
                float(needs.fat_g)
            ) {
                self.result = {
                    "ok": True,
                    "calories_per_day": needs.calories_per_day,
                    "protein_g": needs.protein_g,
                    "carbs_g": needs.carbs_g,
                    "fat_g": needs.fat_g,
                    "notes": needs.notes
                };
                return;
            }
            llm_error = "LLM returned empty macro targets";
        } except Exception as e {
            llm_error = str(e);
        }
        self.result = _deterministic_macro_needs(profile_obj, llm_error);
    }

    can report_result with Root exit {
        if not self.did_generate {
            report {"ok": False, "error": "No user profile found"};
            return;
        }
        report self.result;
    }
}

def _nutrition_to_float(raw: any, fallback: float = 0.0) -> float {
    try {
        return float(raw);
    } except Exception as _e {
        return fallback;
    }
}

def _nutrition_to_int(raw: any, fallback: int = 0) -> int {
    try {
        return int(raw);
    } except Exception as _e {
        return fallback;
    }
}

def _nutrition_pad2(raw: any) -> str {
    text = "0" + str(_nutrition_to_int(raw, 0));
    return text[-2:];
}

def _nutrition_day_name_for_date(day_date: any) -> str {
    names: list = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    idx = _nutrition_to_int(day_date.weekday(), 0);
    if idx < 0 or idx >= len(names) {
        return "Day";
    }
    return names[idx];
}

def _nutrition_date_key_for_date(day_date: any) -> str {
    return "{}-{}-{}".format(
        str(day_date.year),
        _nutrition_pad2(day_date.month),
        _nutrition_pad2(day_date.day)
    );
}

def _nutrition_day_label_for_date(day_date: any) -> str {
    return "{} {}/{}".format(
        _nutrition_day_name_for_date(day_date),
        str(day_date.month),
        str(day_date.day)
    );
}

def _nutrition_start_of_week(anchor_ms: int = 0) -> any {
    anchor_dt = datetime.datetime.now();
    if anchor_ms > 0 {
        anchor_dt = datetime.datetime.fromtimestamp(float(anchor_ms) / 1000.0);
    }
    anchor_date = anchor_dt.date();
    return anchor_date - datetime.timedelta(days=anchor_date.weekday());
}

def _blank_nutrition_day(day_date: any) -> dict {
    return {
        "date_key": _nutrition_date_key_for_date(day_date),
        "day": _nutrition_day_name_for_date(day_date),
        "label": _nutrition_day_label_for_date(day_date),
        "calories_consumed": 0.0,
        "protein_consumed": 0.0,
        "carbs_consumed": 0.0,
        "fat_consumed": 0.0,
        "entries": []
    };
}

def _looks_like_nutrition_day(raw: any) -> bool {
    try {
        return str(raw.get("date_key", "")).strip() != "";
    } except Exception as _e {
        return False;
    }
}

def _normalize_nutrition_recipe_entry(raw: any) -> dict {
    return {
        "recipe_id": str(raw.get("recipe_id", "")).strip(),
        "title": str(raw.get("title", "Recipe")).strip(),
        "calories": _nutrition_to_float(raw.get("calories", 0.0), 0.0),
        "protein_g": _nutrition_to_float(raw.get("protein_g", 0.0), 0.0),
        "carbs_g": _nutrition_to_float(raw.get("carbs_g", 0.0), 0.0),
        "fat_g": _nutrition_to_float(raw.get("fat_g", 0.0), 0.0),
        "meal_type": str(raw.get("meal_type", "")).strip().lower(),
        "made_at_ms": _nutrition_to_int(raw.get("made_at_ms", 0), 0)
    };
}

def _normalized_nutrition_entries(raw: any) -> list {
    entries: list = [];
    try {
        for row in raw {
            entries.append(_normalize_nutrition_recipe_entry(row));
        }
    } except Exception as _e {
        return entries;
    }
    return entries;
}

def _normalize_nutrition_day(raw: any, fallback_date: any = None) -> dict {
    day_date = fallback_date;
    if day_date == None {
        day_date = datetime.datetime.now().date();
    }

    date_key = str(raw.get("date_key", "")).strip();
    if date_key == "" {
        date_key = _nutrition_date_key_for_date(day_date);
    }

    day_name = str(raw.get("day", "")).strip();
    if day_name == "" {
        day_name = _nutrition_day_name_for_date(day_date);
    }

    label_text = str(raw.get("label", "")).strip();
    if label_text == "" {
        label_text = _nutrition_day_label_for_date(day_date);
    }

    return {
        "date_key": date_key,
        "day": day_name,
        "label": label_text,
        "calories_consumed": _nutrition_to_float(raw.get("calories_consumed", 0.0), 0.0),
        "protein_consumed": _nutrition_to_float(raw.get("protein_consumed", 0.0), 0.0),
        "carbs_consumed": _nutrition_to_float(raw.get("carbs_consumed", 0.0), 0.0),
        "fat_consumed": _nutrition_to_float(raw.get("fat_consumed", 0.0), 0.0),
        "entries": _normalized_nutrition_entries(raw.get("entries", []))
    };
}

def _merge_nutrition_daily_history(existing: list = [], weekly: list = []) -> list {
    merged: list = [];
    index_by_key: dict = {};

    for row in existing {
        if not _looks_like_nutrition_day(row) {
            continue;
        }
        normalized = _normalize_nutrition_day(row);
        date_key = str(normalized.get("date_key", "")).strip();
        if date_key == "" {
            continue;
        }
        index_by_key[date_key] = len(merged);
        merged.append(normalized);
    }

    for row in weekly {
        if not _looks_like_nutrition_day(row) {
            continue;
        }
        normalized = _normalize_nutrition_day(row);
        date_key = str(normalized.get("date_key", "")).strip();
        if date_key == "" {
            continue;
        }
        existing_idx = _nutrition_to_int(index_by_key.get(date_key, -1), -1);
        if existing_idx >= 0 and existing_idx < len(merged) {
            merged[existing_idx] = normalized;
        } else {
            index_by_key[date_key] = len(merged);
            merged.append(normalized);
        }
    }
    return merged;
}

def _current_nutrition_week(daily_history: list = []) -> list {
    saved_by_key: dict = {};
    for row in daily_history {
        if not _looks_like_nutrition_day(row) {
            continue;
        }
        normalized = _normalize_nutrition_day(row);
        date_key = str(normalized.get("date_key", "")).strip();
        if date_key != "" {
            saved_by_key[date_key] = normalized;
        }
    }

    week_start = _nutrition_start_of_week();
    history: list = [];
    for idx=0 to idx<7 by idx+=1 {
        day_date = week_start + datetime.timedelta(days=idx);
        date_key = _nutrition_date_key_for_date(day_date);
        day_row = saved_by_key.get(date_key, None);
        if day_row == None {
            history.append(_blank_nutrition_day(day_date));
        } else {
            history.append(_normalize_nutrition_day(day_row, day_date));
        }
    }
    return history;
}

def _selected_nutrition_day_key(weekly_history: list, selected_day_index: int) -> str {
    idx = _nutrition_to_int(selected_day_index, 0);
    if idx < 0 or idx >= len(weekly_history) {
        return "";
    }
    try {
        return str(weekly_history[idx].get("date_key", "")).strip();
    } except Exception as _e {
        return "";
    }
}

def _selected_nutrition_day_index(
    weekly_history: list,
    selected_day_key: str = "",
    fallback_index: int = 0
) -> int {
    normalized_key = str(selected_day_key).strip();
    if normalized_key != "" {
        idx = 0;
        for row in weekly_history {
            try {
                if str(row.get("date_key", "")).strip() == normalized_key {
                    return idx;
                }
            } except Exception as _e {
                0;
            }
            idx += 1;
        }
    }

    fallback = _nutrition_to_int(fallback_index, 0);
    if fallback >= 0 and fallback < len(weekly_history) {
        return fallback;
    }

    today_key = _nutrition_date_key_for_date(datetime.datetime.now().date());
    idx = 0;
    for row in weekly_history {
        try {
            if str(row.get("date_key", "")).strip() == today_key {
                return idx;
            }
        } except Exception as _e {
            0;
        }
        idx += 1;
    }
    return 0;
}

# Persisted per-user pantry state.
node PantryState {
    has version: int = 0;
    has items: list = [];
}

# Persisted per-user nutrition state.
node NutritionState {
    has selected_day_index: int = 0;
    has selected_day_key: str = "";
    has weekly_history: list = [];
    has daily_history: list = [];
    has macro_targets: dict = {};
}

walker SavePantryState {
    has items: list;
    has version: int = 0;
    has pantry_nodes: list = [];
    has current_version: int = -1;
    has current_count: int = 0;
    has found_current: bool = False;
    has save_error: str = "";

    can save with Root entry {
        try {
            visit [-->];
        } except Exception as e {
            self.save_error = str(e);
        }
    }

    can collect_existing with PantryState entry {
        self.pantry_nodes.append(here);
        if here.version >= self.current_version {
            self.current_version = here.version;
            self.current_count = len(here.items);
            self.found_current = True;
        }
    }

    can finish with Root exit {
        if self.save_error {
            report {"saved": False, "error": self.save_error};
            return;
        }
        if self.version < self.current_version {
            report {
                "saved": False,
                "stale": True,
                "count": self.current_count,
                "version": self.current_version
            };
            return;
        }
        if self.found_current and self.version == self.current_version {
            report {
                "saved": True,
                "duplicate": True,
                "count": self.current_count,
                "version": self.current_version
            };
            return;
        }
        try {
            if len(self.pantry_nodes) > 0 {
                primary = self.pantry_nodes[0];
                primary.items = self.items;
                primary.version = self.version;

                idx = 0;
                for pantry_node in self.pantry_nodes {
                    if idx > 0 {
                        del pantry_node;
                    }
                    idx += 1;
                }
                save(primary);
            } else {
                new_nodes = here ++> PantryState(items=self.items, version=self.version);
                save(new_nodes[0]);
            }
            commit();
            report {"saved": True, "count": len(self.items), "version": self.version};
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }
}

walker GetPantryState {
    has items: list = [];
    has version: int = 0;

    can collect with Root entry {
        visit [-->];
    }

    can read with PantryState entry {
        if here.version >= self.version {
            self.items = here.items;
            self.version = here.version;
        }
    }

    can done with Root exit {
        report {"items": self.items, "version": self.version};
    }
}

walker ClearPantryState {
    can collect with Root entry {
        visit [-->];
    }

    can clear with PantryState entry {
        del here;
    }

    can done with Root exit {
        report {"cleared": True};
    }
}

walker SaveNutritionState {
    has selected_day_index: int;
    has weekly_history: list;
    has macro_targets: dict = {};
    has nutrition_nodes: list = [];
    has save_error: str = "";

    can save with Root entry {
        try {
            visit [-->];
        } except Exception as e {
            self.save_error = str(e);
        }
    }

    can collect_existing with NutritionState entry {
        self.nutrition_nodes.append(here);
    }

    can finish with Root exit {
        if self.save_error {
            report {"saved": False, "error": self.save_error};
            return;
        }
        try {
            merged_daily_history = _merge_nutrition_daily_history([], self.weekly_history);
            selected_day_key = _selected_nutrition_day_key(self.weekly_history, self.selected_day_index);
            if len(self.nutrition_nodes) > 0 {
                primary = self.nutrition_nodes[0];
                prior_daily_history: list = [];
                prior_selected_day_key = "";
                try {
                    prior_daily_history = primary.daily_history;
                } except Exception as _e {
                    prior_daily_history = [];
                }
                try {
                    prior_selected_day_key = str(primary.selected_day_key).strip();
                } except Exception as _e {
                    prior_selected_day_key = "";
                }
                merged_daily_history = _merge_nutrition_daily_history(prior_daily_history, self.weekly_history);
                if selected_day_key == "" {
                    selected_day_key = prior_selected_day_key;
                }
                primary.selected_day_index = _selected_nutrition_day_index(
                    _current_nutrition_week(merged_daily_history),
                    selected_day_key,
                    self.selected_day_index
                );
                primary.selected_day_key = selected_day_key;
                primary.weekly_history = _current_nutrition_week(merged_daily_history);
                primary.daily_history = merged_daily_history;
                primary.macro_targets = self.macro_targets;

                idx = 0;
                for nutrition_node in self.nutrition_nodes {
                    if idx > 0 {
                        del nutrition_node;
                    }
                    idx += 1;
                }
                save(primary);
            } else {
                new_nodes = here ++> NutritionState(
                    selected_day_index=_selected_nutrition_day_index(
                        _current_nutrition_week(merged_daily_history),
                        selected_day_key,
                        self.selected_day_index
                    ),
                    selected_day_key=selected_day_key,
                    weekly_history=_current_nutrition_week(merged_daily_history),
                    daily_history=merged_daily_history,
                    macro_targets=self.macro_targets
                );
                save(new_nodes[0]);
            }
            commit();
            report {"saved": True};
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }
}

walker GetNutritionState {
    has selected_day_index: int = 0;
    has weekly_history: list = [];
    has selected_day_key: str = "";
    has daily_history: list = [];
    has macro_targets: dict = {};

    can collect with Root entry {
        visit [-->];
    }

    can read with NutritionState entry {
        saved_daily_history: list = [];
        saved_selected_day_key = "";
        try {
            saved_daily_history = here.daily_history;
        } except Exception as _e {
            saved_daily_history = [];
        }
        try {
            saved_selected_day_key = str(here.selected_day_key).strip();
        } except Exception as _e {
            saved_selected_day_key = "";
        }
        merged_daily_history = _merge_nutrition_daily_history(saved_daily_history, here.weekly_history);
        current_week = _current_nutrition_week(merged_daily_history);
        self.selected_day_key = saved_selected_day_key;
        self.daily_history = merged_daily_history;
        self.weekly_history = current_week;
        self.selected_day_index = _selected_nutrition_day_index(
            current_week,
            self.selected_day_key,
            here.selected_day_index
        );
        self.macro_targets = here.macro_targets;
    }

    can done with Root exit {
        report {
            "selected_day_index": self.selected_day_index,
            "weekly_history": self.weekly_history,
            "macro_targets": self.macro_targets
        };
    }
}

walker ClearNutritionState {
    can collect with Root entry {
        visit [-->];
    }

    can clear with NutritionState entry {
        del here;
    }

    can done with Root exit {
        report {"cleared": True};
    }
}
