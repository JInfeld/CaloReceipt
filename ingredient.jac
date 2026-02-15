"""Ingredient module wiring.
Generate a recipe from a user profile and available pantry ingredients.
"""

import from llm_config {
    llm
}

import from user {
    user,
    user_from_dict
}

enum Unit { PIECE, LB, OZ, CUP, TBSP, TSP, CLOVE, BUNCH }

# Pantry/recipe ingredient schema shared by frontend payloads and LLM output.
obj Ingredient {
    has name: str;
    has quantity: float;
    has unit: Unit;
    has cost: float;
    has protein: float;
    has carb: float;
    has fat: float;
}

sem Ingredient.cost = "Estimated cost in USD";
sem Ingredient.protein = "Estimated amount of protein in grams";
sem Ingredient.carb = "Estimated amount of carbohydrate in grams";
sem Ingredient.fat = "Estimated amount of fat in grams";

obj RecipePlan {
    has recipe_name: str;
    has instructions: list[str];
    has recipe_ingredients: list[Ingredient];
    has total_calories: float;
    has total_protein_g: float;
    has total_carbs_g: float;
    has total_fat_g: float;
}

"""Generate a recipe using the user's profile and pantry ingredients."""
def generate_recipe(profile: user, pantry_ingredients: list[Ingredient]) -> RecipePlan by llm();

# Persisted recipe summary node.
node Recipe {
    has name: str,
        instructions: list[str],
        total_calories: float,
        total_protein_g: float,
        total_carbs_g: float,
        total_fat_g: float;
}

# Persisted ingredient rows for the latest generated recipe.
node MealIngredient {
    has name: str,
        quantity: float,
        unit: str,
        cost: float,
        protein: float,
        carb: float,
        fat: float;
}

# Main recipe generation workflow:
# 1) clear old recipe state
# 2) generate new recipe with LLM
# 3) persist recipe + ingredients
# 4) return response payload for frontend rendering
walker:pub GenerateRecipeFromPantry {
    has profile: dict;
    has pantry_ingredients: list[Ingredient];

    can generate with Root entry {
        visit [-->];

        profile_obj = user_from_dict(self.profile);
        plan = generate_recipe(profile_obj, self.pantry_ingredients);

        here ++> Recipe(
            name=plan.recipe_name,
            instructions=plan.instructions,
            total_calories=plan.total_calories,
            total_protein_g=plan.total_protein_g,
            total_carbs_g=plan.total_carbs_g,
            total_fat_g=plan.total_fat_g
        );

        result: list = [];
        for ing in plan.recipe_ingredients {
            ing_data = {
                "name": ing.name,
                "quantity": ing.quantity,
                "unit": str(ing.unit).split(".")[-1].lower(),
                "cost": ing.cost,
                "protein": ing.protein,
                "carb": ing.carb,
                "fat": ing.fat
            };
            here ++> MealIngredient(
                name=ing_data["name"],
                quantity=ing_data["quantity"],
                unit=ing_data["unit"],
                cost=ing_data["cost"],
                protein=ing_data["protein"],
                carb=ing_data["carb"],
                fat=ing_data["fat"]
            );
            result.append(ing_data);
        }

        report {
            "recipe_name": plan.recipe_name,
            "instructions": plan.instructions,
            "ingredients": result,
            "total_calories": plan.total_calories,
            "total_protein_g": plan.total_protein_g,
            "total_carbs_g": plan.total_carbs_g,
            "total_fat_g": plan.total_fat_g
        };
    }

    can clear_old_recipe with Recipe entry {
        # Keep only the latest generated recipe.
        del here;
    }

    can clear_old_ingredients with MealIngredient entry {
        # Keep ingredient list aligned with latest generated recipe.
        del here;
    }
}

# Read back the latest generated recipe from graph storage.
walker:pub ListGeneratedRecipe {
    has recipe: dict = {};
    has ingredients: list = [];

    can collect with Root entry {
        visit [-->];
    }

    can read_recipe with Recipe entry {
        self.recipe = {
            "recipe_name": here.name,
            "instructions": here.instructions,
            "total_calories": here.total_calories,
            "total_protein_g": here.total_protein_g,
            "total_carbs_g": here.total_carbs_g,
            "total_fat_g": here.total_fat_g
        };
    }

    can read_ingredients with MealIngredient entry {
        self.ingredients.append({
            "name": here.name,
            "quantity": here.quantity,
            "unit": here.unit,
            "cost": here.cost,
            "protein": here.protein,
            "carb": here.carb,
            "fat": here.fat
        });
    }

    can report_all with Root exit {
        self.recipe["ingredients"] = self.ingredients;
        report self.recipe;
    }
}

# Clear persisted recipe state.
walker:pub ClearGeneratedRecipe {
    can collect with Root entry {
        visit [-->];
    }

    can clear_recipe with Recipe entry {
        del here;
    }

    can clear_ingredients with MealIngredient entry {
        del here;
    }

    can done with Root exit {
        report {"cleared": True};
    }
}
