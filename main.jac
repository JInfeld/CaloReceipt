"""Main entry point for CaloReceipt."""

cl import from frontend { app as ClientApp }
cl {
    # Root client app mount used by f"jac start".
    def:pub app() -> JsxElement {
        return <ClientApp />;
    }
}

import from uuid { uuid4 }
import from auth_sso { get_sso_providers }
import from llm_config {
    llm
}
# Import walkers so they are registered in the server module graph.
import from user {
    SaveUserProfile,
    GetUserProfile,
    ClearUserProfile,
    GenerateUserMacroNeeds,
    SavePantryState,
    GetPantryState,
    ClearPantryState,
    SaveNutritionState,
    GetNutritionState,
    ClearNutritionState
}
import from ingredient {
    GenerateRecipeFromPantry,
    ListGeneratedRecipe,
    ListRecipeHistory,
    SetRecipeFavorite,
    MarkRecipeMade,
    ComputePantryAfterRecipe,
    SaveRecipeRankingBatch,
    DeleteSavedRecipe,
    ClearGeneratedRecipe,
    ParseReceiptImageToPantry,
    ParseReceiptTextToPantry
}
import from receipt {
    ExtractReceiptText
}
