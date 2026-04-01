import from llm_config {
    llm
}

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

    can collect with Root entry {
        visit [-->];
    }

    can read with UserProfile entry {
        self.profile = {
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
        try {
            needs = generate_calorie_macro_needs(
                user(
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
                )
            );
            self.result = {
                "ok": True,
                "calories_per_day": needs.calories_per_day,
                "protein_g": needs.protein_g,
                "carbs_g": needs.carbs_g,
                "fat_g": needs.fat_g,
                "notes": needs.notes
            };
        } except Exception as e {
            self.result = {
                "ok": False,
                "error": str(e)
            };
        }
    }

    can report_result with Root exit {
        if not self.did_generate {
            report {"ok": False, "error": "No user profile found"};
            return;
        }
        report self.result;
    }
}

# Persisted per-user pantry state.
node PantryState {
    has version: int = 0;
    has items: list = [];
}

# Persisted per-user nutrition state.
node NutritionState {
    has selected_day_index: int;
    has weekly_history: list = [];
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
            if len(self.nutrition_nodes) > 0 {
                primary = self.nutrition_nodes[0];
                primary.selected_day_index = self.selected_day_index;
                primary.weekly_history = self.weekly_history;

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
                    selected_day_index=self.selected_day_index,
                    weekly_history=self.weekly_history
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

    can collect with Root entry {
        visit [-->];
    }

    can read with NutritionState entry {
        self.selected_day_index = here.selected_day_index;
        self.weekly_history = here.weekly_history;
    }

    can done with Root exit {
        report {
            "selected_day_index": self.selected_day_index,
            "weekly_history": self.weekly_history
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
