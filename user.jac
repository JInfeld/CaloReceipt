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
        username=username_text,
        dietary_restrictions=profile["dietary_restrictions"],
        allergies=profile["allergies"],
        fitness_level=fitness_val,
        goal=goal_val
    );
}

sem user.height = "User height in inches";
sem user.weight = "User weight in pounds";
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
        username: str = "";
}


# --- User Walkers ---
# Upsert a single persistent user profile node in graph storage.
walker SaveUserProfile {
    has profile: dict;

    can save with Root entry {
        try {
            profile_obj = user_from_dict(self.profile);
            # Keep only one user profile in the graph.
            visit [-->];
            here ++> UserProfile(
                age=profile_obj.age,
                sex=profile_obj.sex,
                height=profile_obj.height,
                weight=profile_obj.weight,
                dietary_restrictions=profile_obj.dietary_restrictions,
                allergies=profile_obj.allergies,
                fitness_level=profile_obj.fitness_level,
                goal=profile_obj.goal,
                username=profile_obj.username
            );
            report {"saved": True};
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }

    can clear_old with UserProfile entry {
        # Guarantee one active profile so downstream macro/recipe calls are deterministic.
        del here;
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
    has items: list = [];
}

# Persisted per-user nutrition state.
node NutritionState {
    has selected_day_index: int;
    has weekly_history: list = [];
}

walker SavePantryState {
    has items: list;

    can save with Root entry {
        try {
            visit [-->];
            here ++> PantryState(items=self.items);
            report {"saved": True, "count": len(self.items)};
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }

    can clear_old with PantryState entry {
        del here;
    }
}

walker GetPantryState {
    has items: list = [];

    can collect with Root entry {
        visit [-->];
    }

    can read with PantryState entry {
        self.items = here.items;
    }

    can done with Root exit {
        report {"items": self.items};
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

    can save with Root entry {
        try {
            visit [-->];
            here ++> NutritionState(
                selected_day_index=self.selected_day_index,
                weekly_history=self.weekly_history
            );
            report {"saved": True};
        } except Exception as e {
            report {"saved": False, "error": str(e)};
        }
    }

    can clear_old with NutritionState entry {
        del here;
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
