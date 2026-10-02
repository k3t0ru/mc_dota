package dev.mcdota.mixin;

import net.minecraft.client.MouseHandler;
import net.minecraft.client.input.MouseButtonInfo;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Invoker;

// Lets MouseInput feed menus (inventory, crafting) the cursor and clicks GLFW never sees in the off-screen window.
@Mixin(MouseHandler.class)
public interface MouseHandlerInvoker {
	@Invoker("onMove") void mcdota$move(long window, double x, double y);
	@Invoker("onButton") void mcdota$button(long window, MouseButtonInfo button, int action);
}
