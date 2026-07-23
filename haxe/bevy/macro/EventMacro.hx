package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

class EventMacro {
    public static function send(world:Expr, event:Expr, ?tickOffset:Expr):Expr {
        final type = switch (event.expr) {
            case ENew(path, _): Context.resolveType(TPath(path), event.pos);
            case ECheckType(_, complex) | EParenthesis({expr:ECheckType(_, complex)}):
                Context.resolveType(complex, event.pos);
            default: Context.typeof(event);
        }
        final eventType = TypeTools.toComplexType(type);
        if (eventType == null)
            Context.error('Cannot create an event channel for ${TypeTools.toString(type)}', event.pos);
        final eventId = EventTypeRegistry.register(type, event.pos);
        final offset = if (tickOffset == null) macro 0 else switch (tickOffset.expr) {
            case EConst(CIdent("null")): macro 0;
            default: tickOffset;
        }
        return macro {
            final __bevyEvent = $event;
            final __bevyEventChannel:bevy.EventChannel<$eventType> =
                cast $world.eventBus.channelUntyped($v{eventId});
            __bevyEventChannel.emit(__bevyEvent, $offset);
            __bevyEvent;
        };
    }
}
#end
