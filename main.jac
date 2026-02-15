"""Main entry point for CaloReceipt."""

cl {
    import from frontend { app as ClientApp }

    # Root client app mount used by `jac start`.
    def:pub app -> object {
        return
            <ClientApp />;
    }
}

import from uuid { uuid4 }
import from llm_config {
    llm
}
# Import walkers so they are registered in the server module graph.
import from user {
    SaveUserProfile,
    GetUserProfile,
    ClearUserProfile,
    GenerateUserMacroNeeds
}
import from ingredient {
    GenerateRecipeFromPantry,
    ListGeneratedRecipe,
    ClearGeneratedRecipe
}
