"""Main entry point for CaloReceipt."""

cl {
    import from frontend { app as ClientApp }

    def:pub app -> object {
        return
            <ClientApp />;
    }
}

import from byllm.lib { Model }
import from uuid { uuid4 }

glob llm = Model(model_name="gemini/gemini-2.5-flash");

enum Unit { PIECE, LB, OZ, CUP, TBSP, TSP, CLOVE, BUNCH }

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
sem Ingredient.carbs = "Estimated amount of carbohydrates in grams";
sem Ingredient.protein = "Estimated amount of protein in grams";
sem Ingredient.fat = "Estimated amount of fat in grams";


obj Recipe {
    has name: str;
    has ingredients: list[Ingredient];
    has instructions: str;
    has estimated_cost: float;
    has for_how_many: int;
}


node MealIngredient {
    has name: str,
        quantity: float,
        unit: str,
        cost: float,
        protein: float,
        carb: float,
        fat: float;
}

"""Generate a shopping list of ingredients needed for a described meal."""
def generate_ingredients(meal_description: str) -> list[Ingredient] by llm();

