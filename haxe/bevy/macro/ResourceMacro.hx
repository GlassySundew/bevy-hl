package bevy.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.TypeTools;

class ResourceMacro {

	public static function insert( world : Expr, resourceType : Expr, value : Expr ) : Expr {

		final info = resourceInfo( resourceType );
		final type = info.type;
		return macro {
			final __bevyResource:$type = $value;
			$world.resources.insertDynamic($v{info.name}, __bevyResource);
			__bevyResource;
		};
	}

	public static function get( world : Expr, resourceType : Expr, required : Bool ) : Expr {

		final info = resourceInfo( resourceType );
		final type = info.type;
		return required
			? macro (cast $world.resources.requireDynamic($v{info.name}) : $type)
			: macro (cast $world.resources.getDynamic($v{info.name}) : Null<$type>);
	}

	public static function has( world : Expr, resourceType : Expr ) : Expr {

		final info = resourceInfo( resourceType );
		return macro $world.resources.hasDynamic($v{info.name});
	}

	public static function remove( world : Expr, resourceType : Expr ) : Expr {

		final info = resourceInfo( resourceType );
		final type = info.type;
		return macro (cast $world.resources.removeDynamic($v{info.name}) : Null<$type>);
	}

	static function resourceInfo( expr : Expr ) : { name:String, type:ComplexType } {

		final printed = fieldChain( expr );
		if ( printed == null ) {
			Context.error( "Expected a resource type", expr.pos );
			return { name: "Dynamic", type: macro:Dynamic };
		}
		final resolved = try Context.getType( printed ) catch ( _:Dynamic ) {
			Context.error( 'Resource type not found: $printed', expr.pos );
			Context.getType( "Dynamic" );
		};
		final complex = TypeTools.toComplexType( resolved );
		if ( complex == null )
			Context.error( 'Unsupported resource type ${TypeTools.toString(resolved)}', expr.pos );
		return { name: TypeTools.toString( resolved ), type: complex };
	}

	static function fieldChain( expr : Expr ) : Null<String> {

		return switch ( expr.expr ) {
			case EConst( CIdent( name ) ): name;
			case EField( parent, field ):
				final prefix = fieldChain( parent );
				prefix == null ? null : '$prefix.$field';
			case EParenthesis( inner ): fieldChain( inner );
			default: null;
		}
	}
}
#end
