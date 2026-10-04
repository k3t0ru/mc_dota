package dev.mcdota.mixin;

import net.minecraft.world.level.block.state.BlockBehaviour;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// No block gives light in this world: Minecraft draws none of it (Dota does, with its own light), and a torch placed
// made Minecraft relight and rebuild the chunks around it: a hitch that jerked Dota's camera (wards are torches)
@Mixin(BlockBehaviour.BlockStateBase.class)
public class NoLightMixin {
	@Inject(method = "getLightEmission", at = @At("HEAD"), cancellable = true)
	private void mcdota$dark(CallbackInfoReturnable<Integer> cir) { cir.setReturnValue(0); }
}
