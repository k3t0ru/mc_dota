package dev.mcdota.mixin;

import dev.mcdota.Sync;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.core.BlockPos;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// Our mining progress (crack stage 0..9, -1 = stopped) goes to Dota, which draws the cracks on its own cube.
@Mixin(ClientLevel.class)
public class ClientLevelMixin {
	@Inject(method = "destroyBlockProgress", at = @At("HEAD"))
	private void mcdota$crack(int breaker, BlockPos pos, int stage, CallbackInfo ci) {
		if (Minecraft.getInstance().player != null && breaker == Minecraft.getInstance().player.getId()) Sync.crack(pos, stage);
	}
}
