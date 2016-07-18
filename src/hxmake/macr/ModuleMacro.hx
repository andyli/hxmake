package hxmake.macr;

import hxmake.utils.Haxelib;
import haxe.macro.Expr.Access;
import hxmake.cli.Debug;
import sys.FileSystem;
import haxe.macro.Compiler;
import haxe.io.Path;
import haxe.macro.Type;
import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;

class ModuleMacro {

	public static function build():Array<Field> {
		var cls:ClassType = Context.getLocalClass().get();
		var pos = Context.currentPos();
		var fields:Array<Field> = Context.getBuildFields();
		cls.meta.add(":keep", [], pos);
		var modulePath = getModulePath(Context.getLocalModule());
		var guessModuleName = modulePath.split("/").pop();
		var childrenExprs:Array<Expr> = [];

		var includes:Array<String> = MacroHelper.extractMetaStrings(cls.meta, ":include");
		for(include in includes) {
			var childModulePath = FileSystem.absolutePath(Path.join([modulePath, include]));
			if(!FileSystem.exists(childModulePath)) {
				Debug.log('[WARNING] Path is not found for include "$include"');
				continue;
			}

			var cp = Path.join([childModulePath, "make"]);
			if(!FileSystem.exists(cp)) {
				Debug.log('[WARNING] Make directory is not found for module "$include"');
				continue;
			}

			Compiler.addClassPath(cp);
			Compiler.include("", true, null, [cp]);
			childrenExprs.push(macro hxmake.Project.connect($v{modulePath}, $v{childModulePath}));
		}

		var makeLibraries = processMakeLibraries(":lib", cls.meta);

		if(!cls.meta.has(":root")) {
			var parentMakeDir = FileSystem.absolutePath(Path.join([modulePath, "..", "make"]));
			if(FileSystem.exists(parentMakeDir) && FileSystem.isDirectory(parentMakeDir)) {
				Compiler.addClassPath(parentMakeDir);
				Compiler.include("", true, null, [parentMakeDir]);
			}
		}

		var tp = {
			name: cls.name,
			pack: cls.pack
		};

		fields.push(MacroHelper.makeInitField(macro {
			var module = @:privateAccess new $tp();
			if(module.name == null) {
				module.name = $v{guessModuleName};
			}
			module.path = $v{modulePath};
			@:privateAccess hxmake.Project.__registerModule(module);
			$b{childrenExprs}
		}, pos));

		transformConstructor(fields);

		return fields;
	}

	static function processMakeLibraries(libraryMeta:String, metaAccess:MetaAccess):Map<String, String> {
		var result:Map<String, String> = new Map();
		var metaList:Array<MetadataEntry> = metaAccess.extract(libraryMeta);
		for(meta in metaList) {
			if(meta.params.length > 0) {
				var libName = exprGetStringConst(meta.params[0]);
				var libPath = exprGetStringConst(meta.params[1]);
				if(libName == null) {
					throw '@$libraryMeta first argument need to be String literal';
				}
				if(includeMakeLibrary(libName, libPath)) {
					result.set(libName, libPath);
				}
			}
			else {
				throw '@$libraryMeta requires at least one argument';
			}
		}
		return result;
	}

	static var _makeLibraries:Array<String> = [];

	static function includeMakeLibrary(name:String, path:String):Bool {
		if(_makeLibraries.indexOf(name) >= 0) {
			return true;
		}

		// TODO: relative path, git, accurate haxelib
		var lp = Haxelib.libPath(name, true);
		if(lp == null) {
			Haxelib.install(name);
			lp = Haxelib.libPath(name, true);
		}
		if(lp == null) {
			return false;
		}
		var cp = Path.join([lp, "makeplugin"]);
		if(FileSystem.exists(cp)) {
			Sys.println('Make Plugin: $name @ $cp');
			Compiler.addClassPath(cp);
		}

		_makeLibraries.push(name);
		return true;
	}

	static function exprGetStringConst(expr:Expr):Null<String> {
		if(expr == null) {
			return null;
		}
		return switch(expr.expr) {
			case EConst(x):
				switch(x) {
					case CString(y): y;
					case _: null;
				}
			case _: null;
		}
	}

	static function transformConstructor(fields:Array<Field>) {
		for(field in fields) {
			if(field.name == "new") {
				field.name = "__initialize";
				field.access = [Access.AOverride];
				// TODO: add more validation at Compile-time
			}
		}

		// and generate default empty constructor as well
		fields.push(MacroHelper.makeEmptyConstructor(Context.currentPos()));
	}

	public static function getModulePath(haxeModulePath:String) {
		var moduleRelativePath = haxeModulePath.replace(".", "/") + ".hx";
		var depth = moduleRelativePath.split("/").length + 1;
		var modulePath:String = Context.resolvePath(moduleRelativePath);
		modulePath = modulePath.replace("\\", "/");
		var parts = modulePath.split("/");
		parts = parts.slice(0, parts.length - depth);
		return parts.join("/");
	}
}
